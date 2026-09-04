"""Development seed script: catalog, fees, demo users, listings, prices, channels."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.app import create_app
from extensions import db
from werkzeug.security import generate_password_hash


def seed():
    from app.models.catalog import Product, ProductCategory, UnitOfMeasure
    from app.models.identity import FarmerProfile, User, UserRole
    from app.models.marketplace import Inventory, Listing
    from datetime import date, datetime, timedelta, timezone

    print("Seeding catalog...")
    cat_crops = ProductCategory.query.filter_by(name="Crops").first()
    if cat_crops is None:
        cat_crops = ProductCategory(name="Crops", slug="crops", icon="🌾")
        db.session.add(cat_crops)
        cat_livestock = ProductCategory(name="Livestock", slug="livestock", icon="🐄")
        cat_seeds = ProductCategory(name="Seeds & Inputs", slug="seeds-inputs", icon="🌱")
        db.session.add_all([cat_livestock, cat_seeds])
        db.session.flush()

    def product(name, slug, emoji, category):
        p = Product.query.filter_by(slug=slug).first()
        if p is None:
            p = Product(name=name, slug=slug, category_id=category.id, emoji=emoji)
            db.session.add(p)
            db.session.flush()
        return p

    crops = cat_crops
    products = {}
    for name, slug, emoji in [
        ("Maize", "maize", "🌽"), ("Beans", "beans", "🫘"), ("Rice", "rice", "🍚"),
        ("Irish Potatoes", "irish-potatoes", "🥔"), ("Bananas", "bananas", "🍌"),
        ("Coffee", "coffee", "☕"), ("Cassava", "cassava", "🍠"),
        ("Tomatoes", "tomatoes", "🍅"), ("Onions", "onions", "🧅"),
    ]:
        products[slug] = product(name, slug, emoji, crops)
    livestock_products = {}
    for name, slug, emoji in [
        ("Cattle", "cattle", "🐄"), ("Goats", "goats", "🐐"),
        ("Chickens", "chickens", "🐔"), ("Pigs", "pigs", "🐖"),
    ]:
        livestock_products[slug] = product(name, slug, emoji,
                                           ProductCategory.query.filter_by(slug="livestock").first())

    def category(name, slug, icon):
        c = ProductCategory.query.filter_by(slug=slug).first()
        if c is None:
            c = ProductCategory(name=name, slug=slug, icon=icon)
            db.session.add(c)
            db.session.flush()
        return c

    # The wider agricultural economy: animal products, processed goods,
    # equipment, rentals, services, transport and storage each live as a real
    # catalog category so the universal listing engine serves every offering.
    for name, slug, icon, rows in [
        ("Animal Products", "animal-products", "🥛", [
            ("Fresh Milk", "fresh-milk", "🥛", "L"),
            ("Eggs", "eggs", "🥚", "crate"),
            ("Honey", "honey", "🍯", "kg"),
        ]),
        ("Processed Products", "processed-products", "📦", [
            ("Cassava Flour", "cassava-flour", "🍞", "bag"),
            ("Maize Flour", "maize-flour", "🌽", "bag"),
        ]),
        ("Farm Equipment", "farm-equipment", "🚜", [
            ("Tractor", "tractor", "🚜", "piece"),
            ("Water Pump", "water-pump", "💧", "piece"),
            ("Knapsack Sprayer", "knapsack-sprayer", "🌿", "piece"),
        ]),
        ("Rentals & Hired Tools", "rentals", "🔧", [
            ("Tractor Hire", "tractor-hire", "🚜", "day"),
            ("Water Pump Hire", "water-pump-hire", "💧", "day"),
        ]),
        ("Farm Services", "farm-services", "🧑‍🌾", [
            ("Ploughing Service", "ploughing-service", "🧑‍🌾", "ha"),
            ("Spraying Service", "spraying-service", "🌿", "ha"),
        ]),
        ("Logistics & Transport", "logistics-transport", "🚚", [
            ("Farm Transport", "farm-transport", "🚚", "trip"),
        ]),
        ("Storage & Facilities", "storage-facilities", "🏠", [
            ("Cold Storage Space", "cold-storage-space", "🧊", "day"),
        ]),
    ]:
        cat = category(name, slug, icon)
        for pname, pslug, emoji, unit in rows:
            p = Product.query.filter_by(slug=pslug).first()
            if p is None:
                db.session.add(Product(name=pname, slug=pslug, category_id=cat.id,
                                       emoji=emoji, default_unit=unit))

    # Seeds & Inputs gains a few stocked items.
    seeds_cat = ProductCategory.query.filter_by(slug="seeds-inputs").first()
    if seeds_cat is not None:
        for pname, pslug, emoji, unit in [
            ("Maize Seeds", "maize-seeds", "🌽", "kg"),
            ("Fertilizer NPK", "fertilizer-npk", "🧪", "bag"),
        ]:
            if Product.query.filter_by(slug=pslug).first() is None:
                db.session.add(Product(name=pname, slug=pslug, category_id=seeds_cat.id,
                                       emoji=emoji, default_unit=unit))

    for code, label, dimension in [
        ("kg", "Kilogram", "mass"), ("g", "Gram", "mass"), ("t", "Metric tonne", "mass"),
        ("L", "Litre", "volume"), ("piece", "Piece", "count"),
        ("crate", "Crate", "count"), ("bag", "Bag (50kg)", "count"),
        ("day", "Day", "time"), ("hour", "Hour", "time"), ("week", "Week", "time"),
        ("ha", "Hectare", "area"), ("trip", "Trip", "service"),
    ]:
        if UnitOfMeasure.query.filter_by(code=code).first() is None:
            db.session.add(UnitOfMeasure(code=code, label=label, dimension=dimension))

    from app.services.fee_service import ensure_default_fees

    ensure_default_fees()
    db.session.commit()
    print(f"  {Product.query.count()} products, fees ensured")

    print("Seeding demo users...")
    if User.query.get("platform-fee-sink") is None:
        db.session.add(User(
            id="platform-fee-sink", phone="+250000000000", username="platform-fee-sink",
            full_name="Platform Fees (system)", primary_role="SYSTEM", is_active=True))
        db.session.flush()
    demo = [
        ("+250788111001", "Emmanuel Uwizeye", "emmanuel", "farmer123", ["FARMER"], "Southern", "Huye"),
        ("+250788111002", "Claudine Mukamana", "claudine", "farmer123", ["FARMER"], "Northern", "Musanze"),
        ("+250788111003", "Jean Bosco Niyonzima", "jeanbosco", "buyer1234", ["BUYER"], "Kigali", "Nyarugenge"),
        ("+250788111004", "Grace Ingabire", "grace", "buyer1234", ["BUYER", "WHOLESALER"], "Kigali", "Gasabo"),
        ("+250788111005", "Dr. Alphonse Rwigema", "alphonse", "expert567", ["EXPERT"], "Kigali", "Kicukiro"),
        ("+250788111006", "Eric Habimana", "eric", "logistics1", ["LOGISTICS"], "Kigali", "Nyarugenge"),
        ("+250788111007", "Marie Claire Umutoni", "marieclaire", "coop12345", ["COOPERATIVE"], "Eastern", "Bugesera"),
        ("+250788111008", "Admin Ijwi", "admin", "admin12345", ["ADMIN"], "Kigali", "Nyarugenge"),
    ]
    users = {}
    for phone, display_name, username, password, roles, region, district in demo:
        u = User.query.filter_by(phone=phone).first()
        if u is None:
            u = User(phone=phone, full_name=display_name,
                     username=username, password_hash=generate_password_hash(password),
                     languages="rw", primary_role=roles[0])
            db.session.add(u)
            db.session.flush()
            for r in roles:
                db.session.add(UserRole(user_id=u.id, role=r))
            if "FARMER" in roles:
                fp = FarmerProfile(user_id=u.id, main_crops="maize,beans",
                                   years_experience=5)
                db.session.add(fp)
            if "LOGISTICS" in roles:
                from app.models.identity import LogisticsProfile

                db.session.add(LogisticsProfile(user_id=u.id, company_name="Habimana Transport",
                                                service_areas="Kigali,Southern,Northern"))
        users[username] = u
    db.session.commit()
    print(f"  {User.query.count()} users")

    print("Seeding farms & listings...")
    from app.models.farm import Farm, FarmCrop

    sample_listings = [
        ("claudine", "maize", "Fresh Maize Grade A", 45000, "kg", 1200.0,
         "Dried white maize, moisture 13%, ready for immediate pickup.", "WHOLESALE", None),
        ("claudine", "beans", "Bush Beans - Premium", 78000, "kg", 600.0,
         "Hand-sorted bush beans, no stones, bagged in 50kg sacks.", "WHOLESALE", "AUCTION"),
        ("emmanuel", "irish-potatoes", "Kinigi Potatoes", 32000, "kg", 3000.0,
         "Kinigi variety from volcanic soils of Musanze.", "WHOLESALE", "NEGOTIATION"),
        ("emmanuel", "tomatoes", "Fresh Tomatoes crate", 1500, "crate", 200.0,
         "Grade 1 tomatoes harvested this morning.", "RETAIL", None),
    ]
    for username, pslug, title, price_minor, unit, qty, desc, ltype, auction_type in sample_listings:
        if Listing.query.filter_by(title=title).first():
            continue
        seller = users[username]
        farm = Farm.query.filter_by(owner_id=seller.id).first()
        if farm is None:
            fp = seller.farmer_profile
            farm = Farm(owner_id=seller.id, name=f"{seller.full_name.split()[0]} Main Farm",
                        region=seller.region or "Kigali", district=seller.district or "Nyarugenge",
                        area_value=2.5, area_unit="ha")
            db.session.add(farm)
            db.session.flush()
            crop = FarmCrop(farm_id=farm.id, product_id=products[pslug].id,
                            area_value=1.0, area_unit="ha", state="PLANNED",
                            planting_date=date(2026, 3, 1))
            db.session.add(crop)
            db.session.flush()
        listing = Listing(
            seller_id=seller.id, farm_id=farm.id, product_id=products[pslug].id,
            title=title, description=desc, quantity_value=qty,
            available_quantity=qty, unit_code=unit,
            price_minor=price_minor, currency_code="RWF",
            listing_type=auction_type or "FIXED_PRICE", state="ACTIVE",
            location_region=seller.region or "Kigali", location_district=seller.district,
            available_from=date.today(),
        )
        if auction_type == "AUCTION":
            listing.auction_end_at = datetime.now(timezone.utc) + timedelta(days=3)
            listing.current_bid_minor = price_minor
        db.session.add(listing)
        db.session.flush()
        inv = Inventory(owner_id=seller.id, product_id=products[pslug].id, farm_id=farm.id,
                        batch_ref=f"SEED-{listing.id[:8]}", quantity_value=qty,
                        quantity_total=qty, unit_code=unit)
        db.session.add(inv)
    db.session.commit()
    print(f"  {Listing.query.count()} listings")

    print("Seeding market prices...")
    from app.models.intelligence import MarketPrice

    regions = [("Kigali",), ("Musanze",), ("Huye",)]
    base_prices = {"maize": 42000, "beans": 75000, "rice": 110000, "irish-potatoes": 30000}
    today = date.today()
    added = 0
    for slug, base in base_prices.items():
        prod = Product.query.filter_by(slug=slug).first()
        if prod is None:
            continue
        for i in range(14):
            observed = today - timedelta(days=i)
            drift = 1 + (i % 5 - 2) / 100.0
            mid = int(base * drift)
            for (region,) in regions:
                exists = MarketPrice.query.filter_by(product_id=prod.id, region=region,
                                                     observed_on=observed).first()
                if exists is None:
                    db.session.add(MarketPrice(
                        source_id=_source(db).id, product_id=prod.id, region=region,
                        observed_on=observed, currency_code="RWF", unit_code="kg",
                        price_low_minor=int(mid * 0.95), price_mid_minor=mid,
                        price_high_minor=int(mid * 1.06),
                        market_name=f"{region} Central Market"))
                    added += 1
    db.session.commit()
    print(f"  +{added} price observations")

    print("Seeding advisory & channels...")
    from app.models.community import Channel
    from app.models.intelligence import AdvisoryArticle

    articles = [
        ("Fall armyworm: early detection and control", "pests",
         "Inspect leaves for ragged feeding holes and moist sawdust-like frass...\n\n"
         "**Control:** scout twice weekly; apply recommended insecticides at early whorl stage."),
        ("Post-harvest handling of maize", "post_harvest",
         "Dry maize to 13% moisture before storage. Use hermetic bags to prevent weevil damage."),
        ("When to plant beans this season", "planting",
         "Plant with the first reliable rains; soil should be moist at 5cm depth for 3 consecutive days."),
    ]
    for title, topic, body in articles:
        if AdvisoryArticle.query.filter_by(title=title).first() is None:
            db.session.add(AdvisoryArticle(title=title, topic=topic, body_text=body,
                                           author_id=users["alphonse"].id, published=True))
    for ch_name, ch_slug, ch_type, ch_desc in [
        ("Ministry Announcements", "ministry-announcements", "broadcast",
         "Official notices affecting farmers and traders."),
        ("Daily Market Prices", "daily-market-prices", "market_prices",
         "Automated daily price bulletins per region."),
        ("Weather Warnings", "weather-warnings", "weather_alerts",
         "Heavy rain, wind and frost advisories."),
    ]:
        if Channel.query.filter_by(slug=ch_slug).first() is None:
            db.session.add(Channel(name=ch_name, slug=ch_slug, description=ch_desc,
                                   channel_type=ch_type, creator_id=users["admin"].id))
    db.session.commit()
    print("Seed complete.")


def _source(db):
    from app.models.intelligence import MarketPriceSource

    src = MarketPriceSource.query.filter_by(provider_code="seed_eplatform").first()
    if src is None:
        src = MarketPriceSource(name="e-Soko Nigeria (seed)", provider_code="seed_eplatform")
        db.session.add(src)
        db.session.flush()
    return src


if __name__ == "__main__":
    env = sys.argv[1] if len(sys.argv) > 1 else "development"
    app = create_app(env)
    with app.app_context():
        db.create_all()
        seed()
