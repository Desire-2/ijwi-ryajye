import json
from datetime import date, timedelta

from flask import current_app

from extensions import db
from app.errors import bad_request, not_configured, not_found
from app.models.base import utcnow
from app.models.catalog import Product
from app.models.intelligence import MarketPrice, MarketPriceSource


def ingest_price(source_code, product_id, region, observed_on, currency, unit,
                 low=None, mid=None, high=None, market_name=None, district=None,
                 demand_level=None, supply_level=None):
    source = MarketPriceSource.query.filter_by(provider_code=source_code).first()
    if source is None:
        source = MarketPriceSource(name=source_code.replace("_", " ").title(), provider_code=source_code)
        db.session.add(source)
        db.session.flush()

    if mid is None and low and high:
        mid = (int(low) + int(high)) // 2

    record = MarketPrice(
        product_id=product_id,
        source_id=source.id,
        region=region,
        district=district,
        market_name=market_name,
        observed_on=observed_on or date.today(),
        currency_code=currency,
        unit_code=unit,
        price_low_minor=int(low) if low is not None else None,
        price_mid_minor=int(mid) if mid is not None else None,
        price_high_minor=int(high) if high is not None else None,
        demand_level=demand_level,
        supply_level=supply_level,
    )
    db.session.add(record)
    return record


def query_prices(product_slug=None, region=None, days=30, limit=100):
    q = (
        db.session.query(MarketPrice, Product)
        .join(Product, Product.id == MarketPrice.product_id)
        .order_by(MarketPrice.observed_on.desc())
        .limit(limit * 3)
    )
    if product_slug:
        q = q.filter(Product.slug == product_slug)
    if region:
        q = q.filter(MarketPrice.region == region)

    rows = q.all()
    cutoff = date.today() - timedelta(days=int(days))
    out = []
    for price, product in rows:
        if price.observed_on < cutoff:
            continue
        out.append(
            {
                "product": {"id": product.id, "name": product.name, "slug": product.slug},
                "region": price.region,
                "district": price.district,
                "market_name": price.market_name,
                "observed_on": str(price.observed_on),
                "currency_code": price.currency_code,
                "unit_code": price.unit_code,
                "price_low_minor": price.price_low_minor,
                "price_mid_minor": price.price_mid_minor,
                "price_high_minor": price.price_high_minor,
                "demand_level": price.demand_level,
                "supply_level": price.supply_level,
                "source": {
                    "id": price.source_id,
                    "name": db.session.get(MarketPriceSource, price.source_id).name,
                    "provider_code": db.session.get(MarketPriceSource, price.source_id).provider_code,
                },
                "timestamp": price.created_at.isoformat(),
            }
        )
        if len(out) >= limit:
            break
    return out


def price_trend(product_slug, region):
    rows = query_prices(product_slug=product_slug, region=region, days=90, limit=200)
    by_date = {}
    for r in rows:
        if r["price_mid_minor"]:
            by_date[r["observed_on"]] = r["price_mid_minor"]
    series = sorted(by_date.items())
    if len(series) < 2:
        return {"trend": "insufficient_data", "points": len(series)}
    first = series[0][1]
    last = series[-1][1]
    change_pct = round((last - first) / first * 100, 1) if first else 0
    direction = "up" if change_pct > 1 else ("down" if change_pct < -1 else "stable")
    return {
        "trend": direction,
        "change_percent": change_pct,
        "period_days": 90,
        "observations": len(series),
        "latest_observed_on": series[-1][0],
        "is_estimate": False,
    }


class WeatherProvider:
    name = "abstract"

    def current_and_forecast(self, country, region, district=None):
        raise NotImplementedError


class OpenWeatherProvider(WeatherProvider):
    name = "openweather"

    def __init__(self, api_key):
        self.api_key = api_key

    def _geocode(self, region, country):
        import requests

        resp = requests.get(
            "https://api.openweathermap.org/geo/1.0/direct",
            params={"q": f"{region},{country}", "limit": 1, "appid": self.api_key},
            timeout=10,
        )
        resp.raise_for_status()
        data = resp.json()
        if not data:
            raise bad_request(f"Unknown weather location: {region}, {country}")
        return data[0]["lat"], data[0]["lon"]

    def current_and_forecast(self, country, region, district=None):
        import requests

        lat, lon = self._geocode(district or region, country)
        resp = requests.get(
            "https://api.openweathermap.org/data/2.5/weather",
            params={"lat": lat, "lon": lon, "appid": self.api_key, "units": "metric"},
            timeout=10,
        )
        resp.raise_for_status()
        cur = resp.json()
        forecast_resp = requests.get(
            "https://api.openweathermap.org/data/2.5/forecast",
            params={"lat": lat, "lon": lon, "appid": self.api_key, "units": "metric"},
            timeout=10,
        )
        forecast_resp.raise_for_status()
        forecast_raw = forecast_resp.json().get("list", [])
        daily = []
        for item in forecast_raw[::8][:5]:
            daily.append({
                "datetime": item["dt_txt"],
                "temp_c": item["main"]["temp"],
                "rain_probability_pct": int(item.get("pop", 0) * 100),
                "condition": item["weather"][0]["description"] if item.get("weather") else "",
            })
        main = cur.get("main", {})
        wind = cur.get("wind", {})
        return {
            "provider": self.name,
            "location": {"country": country, "region": region, "district": district},
            "current": {
                "condition_summary": (cur.get("weather") or [{}])[0].get("description", ""),
                "temperature_c": main.get("temp"),
                "humidity_pct": main.get("humidity"),
                "wind_kph": wind.get("speed"),
            },
            "forecast": daily,
            "timestamp": utcnow().isoformat(),
        }


class MetNoProvider(WeatherProvider):
    name = "met_no"

    def __init__(self, user_agent="ijwi-ryajye/1.0"):
        self.user_agent = user_agent

    def current_and_forecast(self, country, region, district=None):
        import requests

        lat, lon = self._geocode_nominatim(district or region, country)
        resp = requests.get(
            f"https://api.met.no/weatherapi/locationforecast/2.0/compact?lat={lat}&lon={lon}",
            headers={"User-Agent": self.user_agent},
            timeout=10,
        )
        resp.raise_for_status()
        timeseries = resp.json()["properties"]["timeseries"]
        first = timeseries[0]["data"]["instant"]["details"]
        daily = [
            {
                "datetime": t["time"],
                "temp_c": t["data"]["instant"]["details"].get("air_temperature"),
                "rain_probability_pct": t["data"].get("next_6_hours", {}).get("probability_of_precipitation", 0),
                "condition": "",
            }
            for t in timeseries[:20:4]
        ]
        return {
            "provider": self.name,
            "location": {"country": country, "region": region, "district": district},
            "current": {
                "condition_summary": "",
                "temperature_c": first.get("air_temperature"),
                "humidity_pct": first.get("relative_humidity"),
                "wind_kph": first.get("wind_speed"),
            },
            "forecast": daily,
            "timestamp": utcnow().isoformat(),
        }

    def _geocode_nominatim(self, place, country):
        import requests

        r = requests.get(
            "https://nominatim.openstreetmap.org/search",
            params={"q": f"{place},{country}", "format": "json", "limit": 1},
            headers={"User-Agent": self.user_agent},
            timeout=10,
        )
        r.raise_for_status()
        data = r.json()
        if not data:
            raise bad_request(f"Unknown weather location: {place}")
        return float(data[0]["lat"]), float(data[0]["lon"])


def get_weather_provider():
    cfg = current_app.config
    name = cfg.get("WEATHER_PROVIDER")
    key = cfg.get("WEATHER_API_KEY")
    if name == "openweather" and key:
        return OpenWeatherProvider(key)
    if name == "met_no":
        return MetNoProvider()
    return None


def weather_for(country, region, district=None):
    provider = get_weather_provider()
    if provider is None:
        raise not_configured("Weather")
    return provider.current_and_forecast(country, region, district)


def advisory_price_interpretation(product_id, region, currency="RWF"):
    rows = query_prices(None, region, days=30, limit=50)
    relevant = [r for r in rows if r["product"]["id"] == product_id]
    mids = [r["price_mid_minor"] for r in relevant if r["price_mid_minor"]]
    if not mids:
        return {"available": False}
    avg = sum(mids) // len(mids)
    return {
        "available": True,
        "average_mid_minor": avg,
        "currency": currency,
        "sample_size": len(mids),
        "note": "Estimate based on reported market observations",
    }
