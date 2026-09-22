import 'package:flutter/material.dart';

import '../models/imovel.dart';

// icone de cada caracteristica do imovel. Uma tabela so, usada no card da
// lista e nos chips do filtro -- eram duas, e a do card nao conhecia
// Elevador, Wi-Fi nem "Exclusivo para Homens": a mesma caracteristica saia
// com etiqueta generica num lugar e com icone no outro
IconData iconeDaTag(String tag) {
  switch (tag) {
    case 'Casa':
      return Icons.house_rounded;
    case 'Apartamento':
      return Icons.apartment_rounded;
    case 'República':
      return Icons.groups_rounded;
    case 'Pensão':
      return Icons.bedroom_parent_rounded;
    case 'Kitnet':
      return Icons.door_back_door_rounded;
    case 'Mobiliado':
      return Icons.chair_rounded;
    case 'Garagem':
      return Icons.garage_rounded;
    case 'Suíte':
      return Icons.king_bed_rounded;
    case 'Elevador':
      return Icons.elevator_rounded;
    case tagPertoDaFaculdade:
      return Icons.school_rounded;
    case 'Exclusivo para Mulheres':
      return Icons.woman_rounded;
    case 'Exclusivo para Homens':
      return Icons.man_rounded;
    default:
      return Icons.label_rounded;
  }
}

// icone de cada conta inclusa -- os mesmos tres da ficha do anuncio, pra
// pessoa reconhecer no filtro o que ja viu no imovel
IconData iconeDaConta(String conta) {
  switch (conta) {
    case contaLuz:
      return Icons.bolt_rounded;
    case contaAgua:
      return Icons.water_drop_rounded;
    case contaWifi:
      return Icons.wifi_rounded;
    default:
      return Icons.receipt_long_rounded;
  }
}
