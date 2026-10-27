import AVFoundation

/// Allège une vidéo avant l'envoi, comme WhatsApp : l'équivalent iOS de
/// `CompressionVideo.kt`.
///
/// Même contrat (canal `rempart/video`) : `mesurer` rend la durée et la
/// taille, `compresser` réencode en MP4 (H.264 + AAC) au débit décidé côté
/// Dart (`compression_video.dart`), le petit côté ramené à `coteCourt`.
///
/// AVAssetReader et AVAssetWriter, et non AVAssetExportSession : les
/// préréglages de celui-ci fixent eux-mêmes le débit, et un 720p y pèse deux à
/// trois fois ce que vise Rempart. Or c'est le débit qui fait tenir une vidéo
/// sous la limite d'envoi du serveur. La composition vidéo fait au passage ce
/// qu'un réencodage naïf raterait : elle redresse une vidéo filmée en
/// portrait (la rotation n'est qu'une consigne dans le fichier), et ramène le
/// HDR des iPhone récents en SDR (BT.709), que tout le monde sait lire.
enum CompressionVideo {
  enum Erreur: LocalizedError {
    case sansImage
    case lecture(String)
    case ecriture(String)

    var errorDescription: String? {
      switch self {
      case .sansImage: return "aucune piste vidéo"
      case .lecture(let detail): return "lecture : \(detail)"
      case .ecriture(let detail): return "écriture : \(detail)"
      }
    }
  }

  /// Durée en millisecondes, largeur et hauteur (avant rotation, comme sur
  /// Android : le plan de compression ne regarde que le petit côté).
  static func mesurer(_ chemin: String) async throws -> [String: Int] {
    let video = AVURLAsset(url: try lisible(chemin))
    let duree = try await video.load(.duration)
    guard let piste = try await video.loadTracks(withMediaType: .video).first else {
      throw Erreur.sansImage
    }
    let taille = try await piste.load(.naturalSize)
    return [
      "dureeMs": Int(CMTimeGetSeconds(duree) * 1000),
      "largeur": Int(taille.width),
      "hauteur": Int(taille.height),
    ]
  }

  /// Réencode [entree] dans [sortie] au [debit] vidéo donné (bits par
  /// seconde), le petit côté ramené à [coteCourt] pixels s'il est non nul et
  /// plus petit que l'original. [progression] reçoit l'avancement, de 0 à 100.
  static func compresser(
    entree: String,
    sortie: String,
    debit: Int,
    coteCourt: Int,
    progression: @escaping (Int) -> Void
  ) async throws {
    let source = AVURLAsset(url: try lisible(entree))
    let duree = try await source.load(.duration)
    guard let pisteVideo = try await source.loadTracks(withMediaType: .video).first else {
      throw Erreur.sansImage
    }
    let pisteSon = try await source.loadTracks(withMediaType: .audio).first
    let (tailleNaturelle, sens, cadence) = try await pisteVideo.load(
      .naturalSize, .preferredTransform, .nominalFrameRate
    )

    // La taille affichée, rotation appliquée, puis ramenée au petit côté visé.
    // La consigne de rotation ne contient pas toujours le déplacement qui
    // ramène l'image dans le cadre (cela dépend de l'appareil qui a filmé) :
    // sans ce recalage sur l'origine, une vidéo portrait sortait en aplat vert,
    // l'image entière hors champ.
    let cadreTourne = CGRect(origin: .zero, size: tailleNaturelle).applying(sens)
    let redresse = sens.concatenating(
      CGAffineTransform(translationX: -cadreTourne.minX, y: -cadreTourne.minY)
    )
    let largeurAffichee = cadreTourne.width
    let hauteurAffichee = cadreTourne.height
    let petitCote = min(largeurAffichee, hauteurAffichee)
    let echelle = coteCourt > 0 && petitCote > CGFloat(coteCourt)
      ? CGFloat(coteCourt) / petitCote : 1
    let largeur = pair(largeurAffichee * echelle)
    let hauteur = pair(hauteurAffichee * echelle)
    let images = cadence > 0 ? min(cadence, 60) : 30

    let composition = AVMutableVideoComposition()
    composition.renderSize = CGSize(width: largeur, height: hauteur)
    composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(images.rounded()))
    composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
    composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
    composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: duree)
    let calque = AVMutableVideoCompositionLayerInstruction(assetTrack: pisteVideo)
    calque.setTransform(redresse.concatenating(CGAffineTransform(scaleX: echelle, y: echelle)), at: .zero)
    instruction.layerInstructions = [calque]
    composition.instructions = [instruction]

    let lecteur = try AVAssetReader(asset: source)
    // BGRA, le format de travail du compositeur : demandées en YUV, les images
    // composées sortaient aux couleurs fausses (vert devenu orange). L'encodeur
    // fait lui-même la conversion, selon les propriétés BT.709 ci-dessous.
    let lectureVideo = AVAssetReaderVideoCompositionOutput(
      videoTracks: [pisteVideo],
      videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    )
    lectureVideo.videoComposition = composition
    lectureVideo.alwaysCopiesSampleData = false
    lecteur.add(lectureVideo)

    let destination = URL(fileURLWithPath: sortie)
    try? FileManager.default.removeItem(at: destination)
    let ecrivain = try AVAssetWriter(outputURL: destination, fileType: .mp4)
    ecrivain.shouldOptimizeForNetworkUse = true
    let ecritureVideo = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: largeur,
      AVVideoHeightKey: hauteur,
      AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: debit,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        AVVideoExpectedSourceFrameRateKey: images,
        AVVideoMaxKeyFrameIntervalDurationKey: 2,
      ],
      AVVideoColorPropertiesKey: [
        AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
      ],
    ])
    ecritureVideo.expectsMediaDataInRealTime = false
    ecrivain.add(ecritureVideo)

    // Le son, décodé puis réencodé en AAC, mono ou stéréo comme la source.
    var son: (AVAssetReaderOutput, AVAssetWriterInput)?
    if let pisteSon {
      let (canaux, frequence) = try await formatDuSon(pisteSon)
      let lectureSon = AVAssetReaderTrackOutput(track: pisteSon, outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVNumberOfChannelsKey: canaux,
        AVSampleRateKey: frequence,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
      ])
      lectureSon.alwaysCopiesSampleData = false
      let ecritureSon = AVAssetWriterInput(mediaType: .audio, outputSettings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVNumberOfChannelsKey: canaux,
        AVSampleRateKey: frequence,
        AVEncoderBitRateKey: 64_000 * canaux,
      ])
      ecritureSon.expectsMediaDataInRealTime = false
      if lecteur.canAdd(lectureSon), ecrivain.canAdd(ecritureSon) {
        lecteur.add(lectureSon)
        ecrivain.add(ecritureSon)
        son = (lectureSon, ecritureSon)
      }
    }

    guard lecteur.startReading() else {
      throw Erreur.lecture(lecteur.error?.localizedDescription ?? "inconnue")
    }
    guard ecrivain.startWriting() else {
      throw Erreur.ecriture(ecrivain.error?.localizedDescription ?? "inconnue")
    }
    ecrivain.startSession(atSourceTime: .zero)

    let total = max(CMTimeGetSeconds(duree), 0.001)
    try await withCheckedThrowingContinuation { (suite: CheckedContinuation<Void, Error>) in
      let groupe = DispatchGroup()
      var dernier = -1
      pomper(lectureVideo, vers: ecritureVideo, groupe: groupe, file: "video") { echantillon in
        // Seule la piste vidéo mesure l'avancement : un pourcentage par
        // palier entier, pas un message par image.
        let instant = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(echantillon))
        let pourcent = Int(min(100, max(0, instant / total * 100)))
        if pourcent != dernier {
          dernier = pourcent
          DispatchQueue.main.async { progression(pourcent) }
        }
      }
      if let son {
        pomper(son.0, vers: son.1, groupe: groupe, file: "son") { _ in }
      }
      groupe.notify(queue: .global(qos: .userInitiated)) {
        if lecteur.status == .failed {
          ecrivain.cancelWriting()
          suite.resume(throwing: Erreur.lecture(lecteur.error?.localizedDescription ?? "inconnue"))
          return
        }
        ecrivain.finishWriting {
          if ecrivain.status == .completed {
            suite.resume()
          } else {
            suite.resume(throwing: Erreur.ecriture(ecrivain.error?.localizedDescription ?? "inconnue"))
          }
        }
      }
    }
  }

  /// Fait passer chaque échantillon de [source] à [destination], au rythme où
  /// l'encodeur les accepte, puis signale la fin au [groupe].
  private static func pomper(
    _ source: AVAssetReaderOutput,
    vers destination: AVAssetWriterInput,
    groupe: DispatchGroup,
    file: String,
    chaque: @escaping (CMSampleBuffer) -> Void
  ) {
    groupe.enter()
    var termine = false
    let fileDAttente = DispatchQueue(label: "rempart.compression.\(file)")
    destination.requestMediaDataWhenReady(on: fileDAttente) {
      while destination.isReadyForMoreMediaData, !termine {
        guard let echantillon = source.copyNextSampleBuffer() else {
          termine = true
          destination.markAsFinished()
          groupe.leave()
          return
        }
        chaque(echantillon)
        // Un refus de l'encodeur passe l'écrivain en échec : on s'arrête, et
        // l'appelant le constate en finissant.
        if !destination.append(echantillon) {
          termine = true
          destination.markAsFinished()
          groupe.leave()
          return
        }
      }
    }
  }

  /// Canaux (1 ou 2) et fréquence de la piste son, bornés à ce qu'un encodeur
  /// AAC accepte partout.
  private static func formatDuSon(_ piste: AVAssetTrack) async throws -> (Int, Double) {
    let descriptions = try await piste.load(.formatDescriptions)
    guard let premiere = descriptions.first,
          let format = CMAudioFormatDescriptionGetStreamBasicDescription(premiere)?.pointee
    else { return (2, 44_100) }
    let canaux = min(max(Int(format.mChannelsPerFrame), 1), 2)
    let frequence = format.mSampleRate > 0 ? min(format.mSampleRate, 48_000) : 44_100
    return (canaux, frequence)
  }

  /// Le fichier sous un nom qu'AVFoundation sait ouvrir.
  ///
  /// Le code Dart écrit la vidéo sous le nom `entree`, sans extension : le
  /// lecteur d'Android analyse le contenu et s'en accommode, AVFoundation
  /// choisit son lecteur d'après l'extension et répond « Cannot Open ». Un
  /// lien `.mov` vers le même fichier suffit (le lecteur QuickTime ouvre aussi
  /// bien un MP4), dans le dossier de travail que Dart vide après coup.
  private static func lisible(_ chemin: String) throws -> URL {
    let url = URL(fileURLWithPath: chemin)
    guard url.pathExtension.isEmpty else { return url }
    let lien = url.appendingPathExtension("mov")
    if !FileManager.default.fileExists(atPath: lien.path) {
      try FileManager.default.linkItem(at: url, to: lien)
    }
    return lien
  }

  /// Arrondi au pair le plus proche : H.264 refuse les dimensions impaires.
  private static func pair(_ valeur: CGFloat) -> Int {
    max(2, Int((valeur / 2).rounded()) * 2)
  }
}
