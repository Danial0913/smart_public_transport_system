class PublicTransportRidership {
  const PublicTransportRidership({
    required this.date,
    this.rapidBusKl,
    this.rapidBusKuantan,
    this.rapidBusPenang,
    this.lrtAmpang,
    this.lrtKelanaJaya,
    this.monorail,
    this.mrtKajang,
    this.mrtPutrajaya,
    this.lrtShahAlam,
    this.ktmEts,
    this.ktmIntercity,
    this.ktmKomuter,
    this.ktmKomuterUtara,
    this.ktmShuttleTebrau,
  });

  final String date;
  final int? rapidBusKl;
  final int? rapidBusKuantan;
  final int? rapidBusPenang;
  final int? lrtAmpang;
  final int? lrtKelanaJaya;
  final int? monorail;
  final int? mrtKajang;
  final int? mrtPutrajaya;
  final int? lrtShahAlam;
  final int? ktmEts;
  final int? ktmIntercity;
  final int? ktmKomuter;
  final int? ktmKomuterUtara;
  final int? ktmShuttleTebrau;

  factory PublicTransportRidership.fromJson(Map<String, dynamic> json) {
    return PublicTransportRidership(
      date: json['date'] as String,
      rapidBusKl: (json['bus_rkl'] as num?)?.toInt(),
      rapidBusKuantan: (json['bus_rkn'] as num?)?.toInt(),
      rapidBusPenang: (json['bus_rpn'] as num?)?.toInt(),
      lrtAmpang: (json['rail_lrt_ampang'] as num?)?.toInt(),
      lrtKelanaJaya: (json['rail_lrt_kj'] as num?)?.toInt(),
      monorail: (json['rail_monorail'] as num?)?.toInt(),
      mrtKajang: (json['rail_mrt_kajang'] as num?)?.toInt(),
      mrtPutrajaya: (json['rail_mrt_pjy'] as num?)?.toInt(),
      lrtShahAlam: (json['rail_lrt_shah_alam'] as num?)?.toInt(),
      ktmEts: (json['rail_ets'] as num?)?.toInt(),
      ktmIntercity: (json['rail_intercity'] as num?)?.toInt(),
      ktmKomuter: (json['rail_komuter'] as num?)?.toInt(),
      ktmKomuterUtara: (json['rail_komuter_utara'] as num?)?.toInt(),
      ktmShuttleTebrau: (json['rail_tebrau'] as num?)?.toInt(),
    );
  }

  Map<String, int?> get services {
    return {
      'Rapid Bus KL': rapidBusKl,
      'Rapid Bus Kuantan': rapidBusKuantan,
      'Rapid Bus Penang': rapidBusPenang,
      'LRT Ampang': lrtAmpang,
      'LRT Kelana Jaya': lrtKelanaJaya,
      'Monorail': monorail,
      'MRT Kajang': mrtKajang,
      'MRT Putrajaya': mrtPutrajaya,
      'LRT Shah Alam': lrtShahAlam,
      'KTM ETS': ktmEts,
      'KTM Intercity': ktmIntercity,
      'KTM Komuter': ktmKomuter,
      'KTM Komuter Utara': ktmKomuterUtara,
      'KTM Shuttle Tebrau': ktmShuttleTebrau,
    };
  }
}

class KtmbRidership {
  const KtmbRidership({
    required this.date,
    required this.service,
    required this.ridership,
  });

  final String date;
  final String service;
  final int ridership;

  factory KtmbRidership.fromJson(Map<String, dynamic> json) {
    return KtmbRidership(
      date: json['date'] as String,
      service: json['service'] as String,
      ridership: (json['ridership'] as num).toInt(),
    );
  }

  String get serviceName {
    switch (service) {
      case 'komuter':
        return 'KTM Komuter';
      case 'komuter_utara':
        return 'KTM Komuter Utara';
      case 'intercity':
        return 'KTM Intercity';
      case 'ets':
        return 'KTM ETS';
      case 'shuttle_tebrau':
        return 'KTM Shuttle Tebrau';
      default:
        return service;
    }
  }
}
