/// Universal listing engine metadata for the Create Listing wizard.
///
/// One engine serves the whole agricultural economy: produce, livestock,
/// animal products, inputs, processed goods, equipment, rentals, services,
/// logistics and storage are all the same listing model — they differ only in
/// which category the product lives in, which extra attributes matter, and
/// which unit/pricing vocabulary fits. Categories and products are loaded from
/// the backend; these profiles only add the per-kind *extra* fields and labels.
library;

enum WizardFieldType { text, number, select }

/// A dynamic category-specific field rendered by the listing form. Values are
/// stored on the listing as scalar `attributes` (backend Listing.attributes).
class WizardField {
  const WizardField({
    required this.key,
    required this.label,
    this.type = WizardFieldType.text,
    this.options = const [],
    this.required = false,
    this.suffix,
    this.hint,
    this.help,
    this.min,
    this.max,
  });

  final String key;
  final String label;
  final WizardFieldType type;
  final List<String> options;
  final bool required;

  /// Optional unit shown after a number input (e.g. "years", "kg").
  final String? suffix;
  final String? hint;
  final String? help;
  final double? min;
  final double? max;

  /// Human label for this attribute when displaying a listing later.
  String get displayLabel => label.replaceFirst(RegExp(r' \(.*\)$'), '');
}

enum ListingKind {
  produce,
  livestock,
  animalProduct,
  input,
  processed,
  equipment,
  rental,
  service,
  logistics,
  storage,
  other,
}

class CategoryProfile {
  const CategoryProfile({
    required this.slug,
    required this.kind,
    this.fields = const [],
    this.graded = false,
    this.certifications = false,
    this.harvestAware = false,
    this.guidance = '',
    this.preferredUnits = const [],
  });

  final String slug;
  final ListingKind kind;

  /// Extra attributes collected on the Details step.
  final List<WizardField> fields;

  /// Produce-style listings offer quality grade + production method.
  final bool graded;

  /// Show the certification selector (organic, fair trade, ...).
  final bool certifications;

  /// Show expected-harvest / available-from fields.
  final bool harvestAware;

  /// One-line prompt shown at the top of the Details step.
  final String guidance;

  /// Unit codes suggested first in the quantity picker.
  final List<String> preferredUnits;

  bool get showQuality => graded || certifications;
}

/// Backend categories are loaded at runtime; these slug-keyed profiles attach
/// the per-kind vocabulary. Unknown/never-seen categories degrade to the
/// generic produce profile.
const Map<String, CategoryProfile> _profiles = {
  'crops': CategoryProfile(
    slug: 'crops', kind: ListingKind.produce, graded: true,
    certifications: true, harvestAware: true,
    guidance: 'Tell buyers the variety, grade and any certification of your harvest.',
    preferredUnits: ['kg', 't', 'bag', 'crate'],
  ),
  'livestock': CategoryProfile(
    slug: 'livestock', kind: ListingKind.livestock,
    guidance: 'Age, weight and health details help buyers judge an animal. Only state what you actually know.',
    preferredUnits: ['piece', 'animal'],
    fields: [
      WizardField(key: 'breed', label: 'Breed', hint: 'e.g. Holstein, Ankole, Boer'),
      WizardField(key: 'sex', label: 'Sex', type: WizardFieldType.select,
          options: ['Female', 'Male']),
      WizardField(key: 'age_years', label: 'Age (years)', type: WizardFieldType.number,
          suffix: 'yrs', min: 0),
      WizardField(key: 'weight_kg', label: 'Live weight', type: WizardFieldType.number,
          suffix: 'kg', min: 0, hint: 'Approximate live weight'),
      WizardField(key: 'vaccinated', label: 'Vaccination status',
          type: WizardFieldType.select,
          options: ['Vaccinated', 'Not vaccinated', 'Unknown']),
      WizardField(key: 'health_notes', label: 'Health notes',
          hint: 'e.g. dewormed, tested — only what you can confirm'),
    ],
  ),
  'animal-products': CategoryProfile(
    slug: 'animal-products', kind: ListingKind.animalProduct, graded: true,
    certifications: true, harvestAware: true,
    guidance: 'Freshness and handling matter here — share harvest/pickup date and grade.',
    preferredUnits: ['L', 'kg', 'crate', 'piece'],
  ),
  'seeds-inputs': CategoryProfile(
    slug: 'seeds-inputs', kind: ListingKind.input, graded: true,
    certifications: true, harvestAware: true,
    preferredUnits: ['kg', 'bag', 'piece'],
    fields: [
      WizardField(key: 'brand', label: 'Brand', hint: 'e.g. ISAR, KOPIA'),
      WizardField(key: 'variety_name', label: 'Variety',
          hint: 'e.g. Longe 5, Nyirakavuna'),
    ],
  ),
  'processed-products': CategoryProfile(
    slug: 'processed-products', kind: ListingKind.processed, graded: true,
    certifications: true,
    guidance: 'Mention processing, packaging size and ingredients where relevant.',
    preferredUnits: ['bag', 'kg', 'piece', 'crate'],
    fields: [
      WizardField(key: 'package_size', label: 'Package size', hint: 'e.g. 25 kg bag, 500 g pack'),
      WizardField(key: 'ingredients', label: 'Ingredients / processing',
          hint: 'Keep it short — full labels stay with the product'),
    ],
  ),
  'farm-equipment': CategoryProfile(
    slug: 'farm-equipment', kind: ListingKind.equipment,
    guidance: 'Describe brand, model and condition so buyers can judge the machine without a visit.',
    preferredUnits: ['piece'],
    fields: [
      WizardField(key: 'condition', label: 'Condition', type: WizardFieldType.select,
          options: ['New', 'Used', 'Refurbished'], required: true),
      WizardField(key: 'brand', label: 'Brand', hint: 'e.g. John Deere, Mahindra, Honda'),
      WizardField(key: 'model', label: 'Model'),
      WizardField(key: 'year', label: 'Year', type: WizardFieldType.number,
          suffix: '', min: 1950),
      WizardField(key: 'hours_used', label: 'Hours used', type: WizardFieldType.number,
          suffix: 'h', min: 0),
      WizardField(key: 'condition_notes', label: 'Condition details',
          hint: 'e.g. new engine 2024, new tyres, serviced'),
    ],
  ),
  'rentals': CategoryProfile(
    slug: 'rentals', kind: ListingKind.rental,
    guidance: 'Rentals sell time, not the machine — set the daily/hourly rate and deposit clearly.',
    preferredUnits: ['day', 'hour', 'week'],
    fields: [
      WizardField(key: 'brand', label: 'Brand'),
      WizardField(key: 'model', label: 'Model'),
      WizardField(key: 'deposit_rwf', label: 'Deposit (RWF)', type: WizardFieldType.number,
          min: 0, help: 'Refundable deposit buyers pay when they book'),
      WizardField(key: 'operator_included', label: 'Operator included',
          type: WizardFieldType.select, options: ['Yes', 'No']),
      WizardField(key: 'availability_window', label: 'Available dates',
          hint: 'e.g. 10–20 September'),
    ],
  ),
  'farm-services': CategoryProfile(
    slug: 'farm-services', kind: ListingKind.service,
    guidance: 'Say where you work, when, and what the buyer gets for the rate.',
    preferredUnits: ['ha', 'hour', 'day', 'trip'],
    fields: [
      WizardField(key: 'service_area', label: 'Service area', required: true,
          hint: 'e.g. Musanze, Burera, Ruhengeri'),
      WizardField(key: 'schedule', label: 'Schedule', hint: 'e.g. Mon–Sat, 7am–5pm'),
      WizardField(key: 'equipment', label: 'Equipment used', hint: 'e.g. 85hp tractor + plough'),
      WizardField(key: 'what_included', label: 'What is included',
          hint: 'e.g. fuel, operator, transport to the site'),
    ],
  ),
  'logistics-transport': CategoryProfile(
    slug: 'logistics-transport', kind: ListingKind.logistics,
    guidance: 'Give the route and truck details so buyers can plan a pickup.',
    preferredUnits: ['trip', 'day', 'kg', 't'],
    fields: [
      WizardField(key: 'route', label: 'Route', required: true,
          hint: 'e.g. Musanze → Kigali'),
      WizardField(key: 'capacity', label: 'Truck capacity', hint: 'e.g. 10 tonnes'),
      WizardField(key: 'vehicle_type', label: 'Vehicle type', hint: 'e.g. pickup, lorry, fridge truck'),
    ],
  ),
  'storage-facilities': CategoryProfile(
    slug: 'storage-facilities', kind: ListingKind.storage,
    guidance: 'Describe the facility, its capacity and what can be stored safely.',
    preferredUnits: ['day', 'month', 't', 'kg'],
    fields: [
      WizardField(key: 'facility_type', label: 'Facility type',
          hint: 'e.g. cold room, dry warehouse, silo'),
      WizardField(key: 'capacity', label: 'Capacity', hint: 'e.g. 20 tonnes'),
      WizardField(key: 'climate_control', label: 'Climate control',
          type: WizardFieldType.select, options: ['Yes', 'No']),
    ],
  ),
};

const CategoryProfile _fallback = CategoryProfile(
  slug: '', kind: ListingKind.other, graded: true,
  certifications: true, harvestAware: true, preferredUnits: ['kg', 't', 'bag'],
);

CategoryProfile profileFor(String? categorySlug) =>
    _profiles[categorySlug] ?? _fallback;

String kindLabel(ListingKind kind) => switch (kind) {
      ListingKind.produce => 'Produce',
      ListingKind.livestock => 'Livestock',
      ListingKind.animalProduct => 'Animal products',
      ListingKind.input => 'Seeds & inputs',
      ListingKind.processed => 'Processed products',
      ListingKind.equipment => 'Equipment',
      ListingKind.rental => 'Rentals',
      ListingKind.service => 'Services',
      ListingKind.logistics => 'Transport',
      ListingKind.storage => 'Storage',
      ListingKind.other => 'Products',
    };

const List<String> qualityGrades = [
  'UNGRADED', 'STANDARD', 'GRADE_B', 'GRADE_A', 'PREMIUM',
];

String gradeLabel(String code) => switch (code) {
      'PREMIUM' => 'Premium',
      'GRADE_A' => 'Grade A',
      'GRADE_B' => 'Grade B',
      'STANDARD' => 'Standard',
      _ => 'Any / ungraded',
    };

const List<String> productionMethods = [
  'ORGANIC', 'CONVENTIONAL', 'INTEGRATED_PEST_MANAGEMENT', 'AGROFORESTRY',
];

const List<String> certifications = [
  'Organic', 'Fair Trade', 'Quality certified', 'Export certified',
];

/// Delivery option codes accepted by the backend (comma-joined column).
const List<(String, String)> deliveryOptions = [
  ('PICKUP', 'Buyer pickup'),
  ('SELLER_DELIVERY', 'Seller delivers'),
  ('BUYER_ARRANGES', 'Buyer arranges transport'),
  ('NEGOTIABLE', 'Negotiable'),
];

/// A lookup of all attribute keys -> display labels so listings render their
/// flexible attributes without storing UI text server-side.
final Map<String, String> _attrLabels = <String, String>{
  for (final p in _profiles.values)
    for (final f in p.fields) f.key: f.displayLabel,
};

String attributeLabel(String key) => _attrLabels[key] ?? key;

/// Formats a stored scalar attribute value for display on a listing.
String formatAttributeValue(String key, dynamic value) {
  if (value == null || value == '') return '';
  if (value is num) {
    if (value == value.roundToDouble() || value is int) {
      return '${(value is int ? value : value.toInt())}';
    }
    return value.toString();
  }
  final s = value.toString();
  if (key == 'deposit_rwf') {
    final major = (num.tryParse(s) ?? 0) / 100;
    return '${major.toStringAsFixed(major == major.roundToDouble() ? 0 : 2)} RWF';
  }
  return s;
}
