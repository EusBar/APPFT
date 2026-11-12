import 'package:fintrack_core/fintrack_core.dart';

/// Fotografia de um ponto turístico, associada a uma moeda.
class CountryPhoto {
  const CountryPhoto(this.asset, this.place, [this.unsplashId]);

  final String asset;
  final String place;

  /// Identificador da fotografia no Unsplash (Licença Unsplash); `null` nas
  /// fotografias fornecidas pelo autor do projeto.
  final String? unsplashId;
}

/// Região mostrada para cada moeda.
String currencyRegion(Currency c) => switch (c.code) {
      'AOA' => 'Angola',
      'USD' => 'Estados Unidos',
      'BRL' => 'Brasil',
      'EUR' => 'Europa',
      'GBP' => 'Reino Unido',
      'ZAR' => 'África do Sul',
      _ => c.code,
    };

/// Cinco maravilhas por moeda, já desfocadas e reduzidas.
const Map<String, List<CountryPhoto>> countryPhotos = {
  'AOA': [
    CountryPhoto('assets/backgrounds/countries/aoa_1.jpg', 'Quedas de Kalandula, Malanje'),
    CountryPhoto('assets/backgrounds/countries/aoa_2.jpg', 'Miradouro da Lua, Luanda'),
    CountryPhoto('assets/backgrounds/countries/aoa_3.jpg', 'Serra da Leba, Huíla'),
    CountryPhoto('assets/backgrounds/countries/aoa_4.jpg', 'Marginal de Luanda'),
    CountryPhoto('assets/backgrounds/countries/aoa_5.jpg', 'Fortaleza de São Miguel, Luanda'),
  ],
  'USD': [
    CountryPhoto('assets/backgrounds/countries/usd_1.jpg', 'Estátua da Liberdade, Nova Iorque', '1485738422979-f5c462d49f74'),
    CountryPhoto('assets/backgrounds/countries/usd_2.jpg', 'Ponte Golden Gate, São Francisco', '1501594907352-04cda38ebc29'),
    CountryPhoto('assets/backgrounds/countries/usd_3.jpg', 'Manhattan, Nova Iorque', '1534430480872-3498386e7856'),
    CountryPhoto('assets/backgrounds/countries/usd_4.jpg', 'Grand Canyon, Arizona', '1615551043360-33de8b5f410c'),
    CountryPhoto('assets/backgrounds/countries/usd_5.jpg', 'Horseshoe Bend, Arizona', '1474044159687-1ee9f3a51722'),
  ],
  'BRL': [
    CountryPhoto('assets/backgrounds/countries/brl_1.jpg', 'Pão de Açúcar, Rio de Janeiro', '1483729558449-99ef09a8c325'),
    CountryPhoto('assets/backgrounds/countries/brl_2.jpg', 'Cristo Redentor, Rio de Janeiro', '1518639192441-8fce0a366e2e'),
    CountryPhoto('assets/backgrounds/countries/brl_3.jpg', 'Baía de Guanabara, Rio de Janeiro', '1516306580123-e6e52b1b7b5f'),
    CountryPhoto('assets/backgrounds/countries/brl_4.jpg', 'Bondinho do Pão de Açúcar', '1544989164-31dc3c645987'),
    CountryPhoto('assets/backgrounds/countries/brl_5.jpg', 'Morro Dois Irmãos, Rio de Janeiro', '1548963670-aaaa8f73a5e3'),
  ],
  'EUR': [
    CountryPhoto('assets/backgrounds/countries/eur_1.jpg', 'Torre Eiffel, Paris', '1502602898657-3e91760cbb34'),
    CountryPhoto('assets/backgrounds/countries/eur_2.jpg', 'Coliseu, Roma', '1552832230-c0197dd311b5'),
    CountryPhoto('assets/backgrounds/countries/eur_3.jpg', 'Santorini, Grécia', '1570077188670-e3a8d69ac5ff'),
    CountryPhoto('assets/backgrounds/countries/eur_4.jpg', 'Elétrico 28, Lisboa', '1585208798174-6cedd86e019a'),
    CountryPhoto('assets/backgrounds/countries/eur_5.jpg', 'Ribeira, Porto', '1555881400-74d7acaacd8b'),
  ],
  'GBP': [
    CountryPhoto('assets/backgrounds/countries/gbp_1.jpg', 'Big Ben, Londres', '1486299267070-83823f5448dd'),
    CountryPhoto('assets/backgrounds/countries/gbp_2.jpg', 'Tower Bridge, Londres', '1543832923-44667a44c804'),
    CountryPhoto('assets/backgrounds/countries/gbp_3.jpg', 'Edimburgo, Escócia', '1506377585622-bedcbb027afc'),
    CountryPhoto('assets/backgrounds/countries/gbp_4.jpg', 'Stonehenge, Inglaterra', '1599833975787-5c143f373c30'),
    CountryPhoto('assets/backgrounds/countries/gbp_5.jpg', 'Rio Tamisa, Londres', '1513635269975-59663e0ac1ad'),
  ],
  'ZAR': [
    CountryPhoto('assets/backgrounds/countries/zar_1.jpg', 'Cidade do Cabo', '1580060839134-75a5edca2e99'),
    CountryPhoto('assets/backgrounds/countries/zar_2.jpg', 'Table Mountain, Cidade do Cabo', '1563656157432-67560011e209'),
    CountryPhoto('assets/backgrounds/countries/zar_3.jpg', 'Doze Apóstolos, Cidade do Cabo', '1576485290814-1c72aa4bbb8e'),
    CountryPhoto('assets/backgrounds/countries/zar_4.jpg', 'Blyde River Canyon', '1484318571209-661cf29a69c3'),
    CountryPhoto('assets/backgrounds/countries/zar_5.jpg', 'Joanesburgo', '1577948000111-9c970dfe3743'),
  ],
};

List<CountryPhoto> photosFor(Currency c) => countryPhotos[c.code] ?? const [];
