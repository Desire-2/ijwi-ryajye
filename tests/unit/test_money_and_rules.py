import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "backend"))

from decimal import Decimal

import pytest

from app.errors import ApiError, bad_request
from app.utils.money import fee_for, from_minor, to_minor, validate_positive_quantity


class _FeeRow:
    def __init__(self, bps, min_fee_minor=None, max_fee_minor=None):
        self.bps = bps
        self.min_fee_minor = min_fee_minor
        self.max_fee_minor = max_fee_minor


def test_to_minor_respects_currency_decimals():
    assert to_minor("12.999", "USD") == 1300
    assert to_minor(10, "RWF") == 10
    assert to_minor("450.5", "KES") == 45050


def test_from_minor():
    assert from_minor(1299, "USD") == Decimal("12.99")
    assert from_minor(500, "RWF") == 500


def test_unsupported_currency_rejected():
    with pytest.raises(Exception):
        to_minor(1, "XYZ")


def test_fee_for_marketplace_sale_default_bps():
    assert fee_for(100_000, None) == 2500


def test_fee_row_overrides_and_clamps():
    row = _FeeRow(bps=100)
    assert fee_for(10_000, row) == 100
    clamped_min = _FeeRow(bps=50, min_fee_minor=200)
    assert fee_for(10_000, clamped_min) == 200
    clamped_max = _FeeRow(bps=500, max_fee_minor=300)
    assert fee_for(100_000, clamped_max) == 300


def test_validate_positive_quantity():
    assert validate_positive_quantity("1.5") == Decimal("1.5")
    with pytest.raises(ApiError):
        validate_positive_quantity(0)
    with pytest.raises(ApiError):
        validate_positive_quantity("abc")
