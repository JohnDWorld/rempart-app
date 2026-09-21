import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:url_launcher/url_launcher.dart';

/// Rendu du `formatted_body` Matrix (sous-ensemble HTML).
///
/// Le SDK aplatit ce HTML en texte brut : gras, citations et blocs de code
/// disparaissent. C'est acceptable pour l'aperçu d'une conversation, pas dans
/// le fil, surtout face à un agent : un LLM répond presque toujours en
/// markdown, converti en HTML par la gateway avant l'envoi.
///
/// Renderer écrit à la main plutôt que `flutter_html` : le sous-ensemble Matrix
/// est petit, et on veut maîtriser l'aspect exact des cadres (code, citation)
/// ainsi que les couleurs selon qu'on est dans sa propre bulle ou dans celle
/// d'en face.
class MessageRiche extends StatefulWidget {
  const MessageRiche({
    required this.formattedBody,
    required this.couleurTexte,
    required this.surFondPropre,
    super.key,
  });

  /// Contenu de `formatted_body`, en HTML Matrix.
  final String formattedBody;

  /// Couleur du texte courant, imposée par la bulle qui nous contient.
  final Color couleurTexte;

  /// Vrai dans une bulle « à moi » (fond coloré) : les cadres doivent alors
  /// jouer sur la transparence plutôt que sur les couleurs du thème, qui
  /// disparaîtraient sur ce fond.
  final bool surFondPropre;

  @override
  State<MessageRiche> createState() => _MessageRicheState();
}

class _MessageRicheState extends State<MessageRiche> {
  /// Reconnaisseurs de tap créés pour les liens du dernier rendu.
  ///
  /// Ils doivent être libérés, sinon chaque reconstruction de la bulle en
  /// abandonne un par lien. La timeline se reconstruit à chaque sync : sur une
  /// conversation nourrie, l'accumulation est réelle.
  final _recognizers = <TapGestureRecognizer>[];

  /// Analyse HTML mémorisée, refaite seulement quand le corps change.
  ///
  /// Sans ce cache, chaque battement de sync réanalyserait le HTML de CHAQUE
  /// bulle visible, pour un résultat identique.
  late dom.Element _corps;
  String? _sourceAnalysee;

  Color get couleurTexte => widget.couleurTexte;

  /// Taille du texte courant, telle que la bulle nous la transmet.
  ///
  /// Titres et code s'en déduisent au lieu de porter des tailles fixes : sans
  /// cela, agrandir le texte dans les réglages laisserait derrière lui les
  /// blocs de code des agents, seuls à garder leur ancienne taille.
  double tailleBase(BuildContext context) =>
      DefaultTextStyle.of(context).style.fontSize ?? 15.5;
  bool get surFondPropre => widget.surFondPropre;

  /// Couleur des liens.
  ///
  /// Le souligné seul ne suffit pas : sur un message d'agent qui cite ses
  /// sources, l'adresse se fondait dans le texte. Dans notre propre bulle, le
  /// fond est deja colore : on eclaircit plutot que d'y poser une seconde
  /// couleur, qui s'y perdrait.
  Color get couleurLien => surFondPropre
      ? couleurTexte
      : Theme.of(context).colorScheme.primary;

  @override
  void dispose() {
    _libererRecognizers();
    super.dispose();
  }

  void _libererRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  /// Attache un reconnaisseur à tous les spans porteurs de texte.
  ///
  /// Un lien peut contenir de la mise en forme (`<a><strong>...`), donc des
  /// spans imbriqués : on descend jusqu'aux feuilles, seules capables de
  /// recevoir un geste.
  List<InlineSpan> _avecReconnaisseur(
    List<InlineSpan> spans,
    TapGestureRecognizer recognizer,
  ) {
    return spans.map((span) {
      if (span is! TextSpan) return span;
      return TextSpan(
        text: span.text,
        style: span.style,
        recognizer: span.text == null ? null : recognizer,
        children: span.children == null
            ? null
            : _avecReconnaisseur(span.children!, recognizer),
      );
    }).toList();
  }

  /// Reconnaisseur de tap sur un lien, retenu pour être libéré plus tard.
  TapGestureRecognizer _reconnaisseurLien(String href) {
    final recognizer = TapGestureRecognizer()
      ..onTap = () async {
        final uri = Uri.tryParse(href);
        if (uri == null) return;
        // On tente l'ouverture sans passer par `canLaunchUrl` : sa réponse
        // dépend des déclarations `queries` du manifeste et vaut « non » un
        // peu trop facilement, ce qui laissait le lien sans effet et sans
        // explication. En cas d'échec, l'adresse part au moins dans le
        // presse-papier plutôt que d'être perdue.
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (_) {
          try {
            await launchUrl(uri);
          } catch (e) {
            debugPrint('MessageRiche: lien non ouvrable ($href) : $e');
            await Clipboard.setData(ClipboardData(text: href));
          }
        }
      };
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  Widget build(BuildContext context) {
    if (_sourceAnalysee != widget.formattedBody) {
      _corps = _extraireCorps(widget.formattedBody);
      _sourceAnalysee = widget.formattedBody;
    }
    // Les reconnaisseurs du rendu precedent ne sont plus references par aucun
    // span : c'est le moment de les rendre.
    _libererRecognizers();
    final blocs = _construireBlocs(context, _corps);

    if (blocs.isEmpty) {
      return const SizedBox.shrink();
    }
    if (blocs.length == 1) {
      return blocs.first;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: blocs,
    );
  }

  /// Analyse le HTML et retire le bloc de réponse citée.
  ///
  /// Matrix préfixe le `formatted_body` d'une réponse d'un `<mx-reply>` qui
  /// reprend le message cité. La bulle dessine déjà son propre cadre de
  /// réponse : sans ce retrait, la citation apparaîtrait deux fois.
  dom.Element _extraireCorps(String source) {
    final document = html_parser.parseFragment(source);
    for (final reply in document.querySelectorAll('mx-reply')) {
      reply.remove();
    }
    final conteneur = dom.Element.tag('div')..nodes.addAll(document.nodes);
    return conteneur;
  }

  List<Widget> _construireBlocs(BuildContext context, dom.Element racine) {
    final blocs = <Widget>[];
    // Les noeuds en ligne qui se suivent sont regroupés dans un seul
    // paragraphe : sans cela, « du **gras** et du texte » se briserait en
    // trois morceaux empilés.
    final enAttente = <dom.Node>[];

    void viderEnAttente() {
      if (enAttente.isEmpty) return;
      final spans = <InlineSpan>[];
      for (final noeud in enAttente) {
        spans.addAll(_spans(context, noeud, const TextStyle()));
      }
      enAttente.clear();
      if (spans.isEmpty) return;
      // Des `<br/>` posés ENTRE deux blocs ne veulent rien dire : les blocs
      // s'espacent déjà d'eux-mêmes. Les rendre littéralement empile des
      // lignes vides, et un agent qui sépare ses paragraphes à la fois par
      // `<p>` et par `<br/>` produit alors un message troué de blancs.
      if (_seulementDesSauts(spans)) return;
      blocs.add(
        Padding(
          padding: EdgeInsets.only(top: blocs.isEmpty ? 0 : 6),
          child: Text.rich(
            TextSpan(children: _compacterSauts(spans)),
            style: TextStyle(color: couleurTexte),
          ),
        ),
      );
    }

    for (final noeud in racine.nodes) {
      if (noeud is dom.Element && _estBloc(noeud.localName)) {
        viderEnAttente();
        final bloc = _bloc(context, noeud, blocs.isEmpty);
        if (bloc != null) blocs.add(bloc);
      } else {
        enAttente.add(noeud);
      }
    }
    viderEnAttente();
    return blocs;
  }

  /// Ces fragments ne portent-ils que des sauts et des espaces ?
  static bool _seulementDesSauts(List<InlineSpan> spans) {
    for (final span in spans) {
      if (span is! TextSpan) return false;
      final texte = span.text ?? '';
      if (span.children?.isNotEmpty ?? false) return false;
      if (texte.replaceAll(RegExp(r'[\s\u00a0]'), '').isNotEmpty) return false;
    }
    return true;
  }

  /// Réduit les sauts consécutifs à un seul.
  ///
  /// Un modèle de langage aère volontiers son texte de deux ou trois lignes
  /// vides ; sur un écran de téléphone, chacune coûte un quart de la hauteur
  /// utile et il faut faire défiler pour lire trois phrases.
  static List<InlineSpan> _compacterSauts(List<InlineSpan> spans) {
    final sortie = <InlineSpan>[];
    var sautPrecedent = false;
    for (final span in spans) {
      final estSaut = span is TextSpan &&
          (span.children?.isEmpty ?? true) &&
          (span.text ?? '').trim().isEmpty &&
          (span.text ?? '').contains('\n');
      if (estSaut && sautPrecedent) continue;
      sautPrecedent = estSaut;
      sortie.add(span);
    }
    return sortie;
  }

  static bool _estBloc(String? balise) => const {
        'pre',
        'blockquote',
        'ul',
        'ol',
        'h1',
        'h2',
        'h3',
        'h4',
        'h5',
        'h6',
        'hr',
        'p',
        'div',
      }.contains(balise);

  Widget? _bloc(BuildContext context, dom.Element element, bool premier) {
    final marge = EdgeInsets.only(top: premier ? 0 : 8);

    switch (element.localName) {
      case 'pre':
        return Padding(padding: marge, child: _BlocCode(element: element));

      case 'blockquote':
        return Padding(
          padding: marge,
          child: _Citation(
            couleurTexte: couleurTexte,
            surFondPropre: surFondPropre,
            child: Text.rich(
              TextSpan(children: _enfants(context, element, const TextStyle())),
              style: TextStyle(color: couleurTexte),
            ),
          ),
        );

      case 'ul':
      case 'ol':
        return Padding(
          padding: marge,
          child: _liste(context, element, ordonnee: element.localName == 'ol'),
        );

      case 'hr':
        return Padding(
          padding: marge,
          child: Divider(color: couleurTexte.withValues(alpha: 0.3), height: 1),
        );

      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        final niveau = int.parse(element.localName!.substring(1));
        return Padding(
          padding: marge,
          child: Text.rich(
            TextSpan(children: _enfants(context, element, const TextStyle())),
            style: TextStyle(
              color: couleurTexte,
              fontWeight: FontWeight.bold,
              // h1 le plus gros, décroissant ensuite, sans jamais descendre
              // sous la taille du texte courant.
              fontSize: math.max(
                tailleBase(context),
                tailleBase(context) * 1.3 - (niveau - 1) * 1.5,
              ),
            ),
          ),
        );

      // <p> et <div> : simples conteneurs, on rend leur contenu.
      default:
        final spans = _enfants(context, element, const TextStyle());
        if (spans.isEmpty) return null;
        // Un paragraphe peut lui-même contenir un bloc (cas d'un HTML mal
        // formé) ; on le laisse au rendu en ligne, qui l'ignorera proprement.
        return Padding(
          padding: marge,
          child: Text.rich(
            TextSpan(children: _compacterSauts(spans)),
            style: TextStyle(color: couleurTexte),
          ),
        );
    }
  }

  Widget _liste(BuildContext context, dom.Element element,
      {required bool ordonnee}) {
    final items = element.children.where((e) => e.localName == 'li').toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ordonnee ? '${i + 1}. ' : '• ',
                  style: TextStyle(color: couleurTexte),
                ),
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: _enfants(context, items[i], const TextStyle()),
                    ),
                    style: TextStyle(color: couleurTexte),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  List<InlineSpan> _enfants(
    BuildContext context,
    dom.Node parent,
    TextStyle style,
  ) {
    final spans = <InlineSpan>[];
    for (final enfant in parent.nodes) {
      spans.addAll(_spans(context, enfant, style));
    }
    return spans;
  }

  /// Convertit un noeud en ligne en spans, en accumulant le style hérité.
  List<InlineSpan> _spans(
    BuildContext context,
    dom.Node noeud,
    TextStyle style,
  ) {
    if (noeud is dom.Text) {
      final texte = noeud.text;
      if (texte.isEmpty) return const [];
      // Une adresse ecrite en clair n'est pas une balise <a> : sans cela, les
      // sources que citent les agents restaient du texte mort, ni cliquable ni
      // visible.
      return spansAvecLiens(
        texte: texte,
        style: style,
        couleurLien: couleurLien,
        reconnaisseur: _reconnaisseurLien,
      );
    }

    if (noeud is! dom.Element) return const [];

    switch (noeud.localName) {
      case 'b':
      case 'strong':
        return _enfants(context, noeud,
            style.merge(const TextStyle(fontWeight: FontWeight.bold)));

      case 'i':
      case 'em':
        return _enfants(context, noeud,
            style.merge(const TextStyle(fontStyle: FontStyle.italic)));

      case 'u':
        return _enfants(context, noeud,
            style.merge(const TextStyle(decoration: TextDecoration.underline)));

      case 's':
      case 'del':
      case 'strike':
        return _enfants(
            context,
            noeud,
            style.merge(
                const TextStyle(decoration: TextDecoration.lineThrough)));

      case 'code':
        return [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _CodeEnLigne(
              texte: noeud.text,
              couleurTexte: couleurTexte,
              surFondPropre: surFondPropre,
            ),
          ),
        ];

      case 'br':
        return const [TextSpan(text: '\n')];

      case 'a':
        final href = noeud.attributes['href'];
        final lien = style.merge(TextStyle(
          color: couleurLien,
          decoration: TextDecoration.underline,
          decorationColor: couleurLien,
        ));
        if (href == null || href.isEmpty) {
          return _enfants(context, noeud, lien);
        }
        // Le reconnaisseur doit être porté par les spans qui contiennent
        // vraiment du texte. Posé sur un span qui n'a que des enfants, il ne
        // sert à rien : au clic, Flutter cherche le span sous le doigt avec
        // `getSpanForPositionVisitor`, qui écarte d'emblée tout span dont
        // `text` est nul. Le lien s'affichait donc souligné, mais mort.
        return _avecReconnaisseur(
          _enfants(context, noeud, lien),
          _reconnaisseurLien(href),
        );

      // Blocs croises en position en ligne : cela arrive avec le HTML d'un
      // autre client, ou d'un agent qui colle son bloc de code au texte. Sans
      // ce traitement, le code perdrait son cadre, son bouton copier et son
      // defilement, pour finir noye dans le paragraphe.
      case 'pre':
        return [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _BlocCode(element: noeud),
          ),
        ];

      case 'blockquote':
        return [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _Citation(
              couleurTexte: couleurTexte,
              surFondPropre: surFondPropre,
              child: Text.rich(
                TextSpan(children: _enfants(context, noeud, const TextStyle())),
                style: TextStyle(color: couleurTexte),
              ),
            ),
          ),
        ];

      // Balise inconnue : on rend son contenu plutôt que de le perdre.
      default:
        return _enfants(context, noeud, style);
    }
  }
}

/// Bloc de code encadré, avec langage et bouton copier.
class _BlocCode extends StatelessWidget {
  const _BlocCode({required this.element});

  final dom.Element element;

  /// Langage déclaré par `class="language-python"`, s'il existe.
  String? get _langue {
    final code = element.querySelector('code');
    final classes = code?.attributes['class'] ?? '';
    for (final classe in classes.split(RegExp(r'\s+'))) {
      if (classe.startsWith('language-')) {
        final nom = classe.substring('language-'.length).trim();
        if (nom.isNotEmpty) return nom;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = element.text.trimRight();
    final langue = _langue;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        // Fond sombre et neutre : un bloc de code doit se détacher de la bulle
        // quelle que soit sa couleur, et rester lisible dans les deux thèmes.
        color: const Color(0xFF1E1E24),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    langue ?? 'code',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white70,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_all_outlined, size: 16),
                  color: Colors.white70,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Copier le code',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Code copié')),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          // Défilement horizontal : une ligne longue ne doit ni être coupée ni
          // élargir la bulle au-delà de l'écran.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: SelectableText(
              code,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.35,
                color: Color(0xFFE6E6EA),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Citation encadrée, barre verticale à gauche.
class _Citation extends StatelessWidget {
  const _Citation({
    required this.child,
    required this.couleurTexte,
    required this.surFondPropre,
  });

  final Widget child;
  final Color couleurTexte;
  final bool surFondPropre;

  @override
  Widget build(BuildContext context) {
    final accent = couleurTexte.withValues(alpha: surFondPropre ? 0.6 : 0.4);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
      decoration: BoxDecoration(
        color: couleurTexte.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: child,
    );
  }
}

/// Code en ligne : fond léger et chasse fixe, sans casser le fil du texte.
class _CodeEnLigne extends StatelessWidget {
  const _CodeEnLigne({
    required this.texte,
    required this.couleurTexte,
    required this.surFondPropre,
  });

  final String texte;
  final Color couleurTexte;
  final bool surFondPropre;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: couleurTexte.withValues(alpha: surFondPropre ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        texte,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: DefaultTextStyle.of(context).style.fontSize != null
              ? DefaultTextStyle.of(context).style.fontSize! * 0.85
              : 13,
          color: couleurTexte,
        ),
      ),
    );
  }
}

/// Repère les adresses écrites en clair dans un texte et les rend cliquables.
///
/// Un agent qui cite ses sources écrit « Source : https://… » : c'est du texte
/// brut, pas une balise `<a>`. Sans ce découpage, l'adresse restait morte, et
/// noire au milieu du message.
///
/// La ponctuation finale est laissée hors du lien : « voir https://exemple.fr. »
/// ne doit pas emporter le point, qui donnerait une adresse fausse.
List<InlineSpan> spansAvecLiens({
  required String texte,
  required TextStyle style,
  required Color couleurLien,
  required TapGestureRecognizer Function(String href) reconnaisseur,
}) {
  final trouves = _motifUrl.allMatches(texte);
  if (trouves.isEmpty) return [TextSpan(text: texte, style: style)];

  final spans = <InlineSpan>[];
  var curseur = 0;
  for (final m in trouves) {
    var url = m.group(0)!;
    var fin = m.end;
    // Une parenthèse fermante n'appartient au lien que si une ouvrante le
    // précède : « (voir https://exemple.fr/a) » ne doit pas la garder.
    while (url.isNotEmpty && _ponctuationFinale.contains(url[url.length - 1])) {
      if (url.endsWith(')') && url.contains('(')) break;
      url = url.substring(0, url.length - 1);
      fin--;
    }
    if (url.isEmpty) continue;
    if (m.start > curseur) {
      spans.add(TextSpan(text: texte.substring(curseur, m.start), style: style));
    }
    spans.add(
      TextSpan(
        text: url,
        style: style.merge(
          TextStyle(
            color: couleurLien,
            decoration: TextDecoration.underline,
            decorationColor: couleurLien,
          ),
        ),
        recognizer: reconnaisseur(url.startsWith('www.') ? 'https://$url' : url),
      ),
    );
    curseur = fin;
  }
  if (curseur < texte.length) {
    spans.add(TextSpan(text: texte.substring(curseur), style: style));
  }
  return spans;
}

/// `www.` sans schéma est reconnu : c'est ainsi qu'on écrit une adresse à la
/// main. Les autres schémas (mailto, ftp) sont volontairement absents : ils
/// n'apparaissent pas dans une conversation, et chacun élargit la surface de ce
/// qu'un message peut faire ouvrir.
final _motifUrl = RegExp(
  r'(?:https?://|www\.)[^\s<>"]+',
  caseSensitive: false,
);

const _ponctuationFinale = '.,;:!?)]}»"\'';

/// Texte brut dont les adresses sont cliquables.
///
/// Jumeau de [MessageRiche] pour les messages sans mise en forme : eux aussi
/// contiennent des adresses, et il n'y a pas de raison qu'elles y soient mortes
/// alors qu'elles vivent dans un message d'agent.
///
/// À état, pour libérer ses reconnaisseurs : la timeline se reconstruit à
/// chaque battement de synchronisation, et sur une conversation nourrie
/// l'accumulation est réelle.
class TexteAvecLiens extends StatefulWidget {
  const TexteAvecLiens({
    required this.texte,
    required this.style,
    required this.surFondPropre,
    super.key,
  });

  final String texte;
  final TextStyle style;

  /// Dans notre propre bulle, le fond est déjà coloré : un lien y garde la
  /// couleur du texte, une seconde couleur s'y perdrait.
  final bool surFondPropre;

  @override
  State<TexteAvecLiens> createState() => _TexteAvecLiensState();
}

class _TexteAvecLiensState extends State<TexteAvecLiens> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  TapGestureRecognizer _reconnaisseur(String href) {
    final recognizer = TapGestureRecognizer()..onTap = () => ouvrirLien(href);
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    final couleurLien = widget.surFondPropre
        ? widget.style.color
        : Theme.of(context).colorScheme.primary;

    return Text.rich(
      TextSpan(
        children: spansAvecLiens(
          texte: widget.texte,
          style: widget.style,
          couleurLien: couleurLien ?? Theme.of(context).colorScheme.primary,
          reconnaisseur: _reconnaisseur,
        ),
      ),
    );
  }
}

/// Ouvre une adresse, ou la copie si rien ne sait l'ouvrir.
///
/// On tente sans passer par `canLaunchUrl` : sa réponse dépend des
/// déclarations `queries` du manifeste et vaut « non » un peu trop facilement,
/// ce qui laissait le lien sans effet et sans explication.
Future<void> ouvrirLien(String href) async {
  final uri = Uri.tryParse(href);
  if (uri == null) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    try {
      await launchUrl(uri);
    } catch (e) {
      debugPrint('Lien non ouvrable ($href) : $e');
      await Clipboard.setData(ClipboardData(text: href));
    }
  }
}
