class FoodServing {
  const FoodServing({required this.label, required this.grams});

  final String label;
  final double grams;
}

class CatalogFood {
  const CatalogFood({
    required this.id,
    required this.name,
    required this.servings,
    required this.energyKcalPer100g,
    required this.proteinGPer100g,
    required this.fiberGPer100g,
  });

  final String id;
  final String name;
  final List<FoodServing> servings;
  final double energyKcalPer100g;
  final double proteinGPer100g;
  final double fiberGPer100g;

  NutritionSnapshot nutritionFor(double grams) => NutritionSnapshot(
    energyKcal: energyKcalPer100g * grams / 100,
    proteinG: proteinGPer100g * grams / 100,
    fiberG: fiberGPer100g * grams / 100,
  );
}

class NutritionSnapshot {
  const NutritionSnapshot({
    required this.energyKcal,
    required this.proteinG,
    required this.fiberG,
  });

  final double energyKcal;
  final double proteinG;
  final double fiberG;

  NutritionSnapshot operator +(NutritionSnapshot other) => NutritionSnapshot(
    energyKcal: energyKcal + other.energyKcal,
    proteinG: proteinG + other.proteinG,
    fiberG: fiberG + other.fiberG,
  );

  static const zero = NutritionSnapshot(energyKcal: 0, proteinG: 0, fiberG: 0);
}

const developmentFoodCatalog = <CatalogFood>[
  CatalogFood(
    id: 'egg_whole_cooked',
    name: 'Boiled egg',
    servings: [
      FoodServing(label: '1 large', grams: 50),
      FoodServing(label: '100 g', grams: 100),
    ],
    energyKcalPer100g: 155,
    proteinGPer100g: 12.6,
    fiberGPer100g: 0,
  ),
  CatalogFood(
    id: 'banana_raw',
    name: 'Banana',
    servings: [
      FoodServing(label: '1 medium', grams: 118),
      FoodServing(label: '100 g', grams: 100),
    ],
    energyKcalPer100g: 89,
    proteinGPer100g: 1.09,
    fiberGPer100g: 2.6,
  ),
  CatalogFood(
    id: 'oats_dry',
    name: 'Oats',
    servings: [
      FoodServing(label: '40 g', grams: 40),
      FoodServing(label: '100 g', grams: 100),
    ],
    energyKcalPer100g: 389,
    proteinGPer100g: 16.9,
    fiberGPer100g: 10.6,
  ),
  CatalogFood(
    id: 'milk_toned',
    name: 'Toned milk',
    servings: [
      FoodServing(label: '250 ml', grams: 250),
      FoodServing(label: '100 ml', grams: 100),
    ],
    energyKcalPer100g: 60,
    proteinGPer100g: 3.2,
    fiberGPer100g: 0,
  ),
  CatalogFood(
    id: 'rice_white_cooked',
    name: 'Cooked white rice',
    servings: [
      FoodServing(label: '1 cup', grams: 158),
      FoodServing(label: '100 g', grams: 100),
    ],
    energyKcalPer100g: 130,
    proteinGPer100g: 2.7,
    fiberGPer100g: 0.4,
  ),
  CatalogFood(
    id: 'lentils_cooked',
    name: 'Cooked lentils',
    servings: [
      FoodServing(label: '1 cup', grams: 198),
      FoodServing(label: '100 g', grams: 100),
    ],
    energyKcalPer100g: 116,
    proteinGPer100g: 9,
    fiberGPer100g: 7.9,
  ),
  CatalogFood(
    id: 'spinach_cooked',
    name: 'Cooked spinach',
    servings: [
      FoodServing(label: '1 cup', grams: 180),
      FoodServing(label: '100 g', grams: 100),
    ],
    energyKcalPer100g: 23,
    proteinGPer100g: 3,
    fiberGPer100g: 2.4,
  ),
  CatalogFood(
    id: 'whole_wheat_bread',
    name: 'Whole-wheat bread',
    servings: [
      FoodServing(label: '1 slice', grams: 28),
      FoodServing(label: '100 g', grams: 100),
    ],
    energyKcalPer100g: 247,
    proteinGPer100g: 13,
    fiberGPer100g: 7,
  ),
];
