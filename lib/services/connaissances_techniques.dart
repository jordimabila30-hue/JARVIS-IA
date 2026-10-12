/// Petite base de connaissances techniques, consultable à la voix.
///
/// Chaque notion a des noms possibles (déjà normalisés : minuscules, sans
/// accents ni ponctuation), une réponse courte et un développement (« dis-m'en
/// plus »). Les textes restent factuels et généraux : JARVIS ne doit jamais
/// inventer.
class Notion {
  const Notion(this.noms, this.courte, this.detail);

  final List<String> noms;
  final String courte;
  final String detail;
}

const List<Notion> connaissancesTechniques = [
  // --- Intelligence artificielle ---------------------------------------------
  Notion(
    ['intelligence artificielle', 'ia', 'l ia', 'une ia'],
    'L’intelligence artificielle regroupe les techniques qui permettent à une '
        'machine de réaliser des tâches qui demandent habituellement de '
        'l’intelligence humaine : comprendre le langage, reconnaître des '
        'images ou prendre des décisions.',
    'La plupart des IA modernes apprennent à partir d’exemples plutôt que de '
        'règles écrites à la main. On distingue l’IA spécialisée, conçue pour '
        'une tâche précise, et l’idée d’une IA générale, capable de tout faire, '
        'qui reste un sujet de recherche.',
  ),
  Notion(
    ['apprentissage automatique', 'machine learning'],
    'L’apprentissage automatique, ou machine learning, consiste à entraîner un '
        'programme sur des données pour qu’il apprenne à faire des prédictions '
        'sans qu’on lui écrive chaque règle.',
    'On distingue trois grandes familles : l’apprentissage supervisé, avec des '
        'exemples étiquetés ; non supervisé, où le modèle cherche lui-même des '
        'regroupements ; et par renforcement, où il apprend par essais, erreurs '
        'et récompenses.',
  ),
  Notion(
    ['reseau de neurones', 'reseaux de neurones', 'neurone artificiel'],
    'Un réseau de neurones est un modèle composé de couches de petites unités '
        'de calcul reliées entre elles, inspiré de façon très simplifiée du '
        'cerveau.',
    'Chaque connexion a un poids. Pendant l’entraînement, ces poids sont '
        'ajustés petit à petit, grâce à la rétropropagation du gradient, pour '
        'réduire l’erreur entre la prédiction et la bonne réponse.',
  ),
  Notion(
    ['modele de langage', 'llm', 'grand modele de langage', 'chatgpt'],
    'Un grand modèle de langage est un réseau de neurones entraîné sur '
        'énormément de texte pour prédire la suite d’un texte, mot après mot.',
    'C’est cette prédiction répétée qui lui permet de répondre, résumer ou '
        'traduire. Il peut se tromper avec assurance : on parle '
        'd’hallucinations. Pour l’instant, aucun modèle de langage n’est '
        'connecté à JARVIS.',
  ),
  Notion(
    ['deep learning', 'apprentissage profond'],
    'L’apprentissage profond, ou deep learning, est l’apprentissage '
        'automatique avec des réseaux de neurones comportant de nombreuses '
        'couches.',
    'Les couches successives apprennent des représentations de plus en plus '
        'abstraites : des contours, puis des formes, puis des objets pour une '
        'image. Il demande beaucoup de données et de puissance de calcul, '
        'souvent des cartes graphiques.',
  ),
  Notion(
    ['reconnaissance vocale', 'speech to text'],
    'La reconnaissance vocale transforme la voix en texte.',
    'Le son du micro est découpé en petits morceaux, analysé par un modèle '
        'acoustique, puis un modèle de langage choisit la phrase la plus '
        'probable. Dans JARVIS sur le Web, ce travail est fait par le service '
        'du navigateur, ce qui demande Internet.',
  ),
  Notion(
    ['synthese vocale', 'text to speech', 'tts'],
    'La synthèse vocale fait l’inverse de la reconnaissance : elle transforme '
        'un texte en voix.',
    'Les voix récentes sont produites par des réseaux de neurones, ce qui les '
        'rend plus naturelles. JARVIS utilise une voix française installée sur '
        'votre système.',
  ),

  // --- Développement ---------------------------------------------------------
  Notion(
    ['flutter'],
    'Flutter est un framework de Google qui permet de créer une application '
        'pour Android, iOS, le Web, Windows, macOS et Linux à partir d’un seul '
        'code.',
    'Flutter dessine lui-même toute l’interface avec son propre moteur de '
        'rendu, ce qui donne le même aspect sur toutes les plateformes. '
        'L’interface est construite avec des widgets. JARVIS est développé '
        'avec Flutter.',
  ),
  Notion(
    ['dart', 'langage dart'],
    'Dart est le langage de programmation créé par Google et utilisé par '
        'Flutter.',
    'Il est typé, avec une sécurité contre les valeurs nulles, et peut être '
        'compilé en code machine pour les applications ou en JavaScript et '
        'WebAssembly pour le Web.',
  ),
  Notion(
    ['widget', 'widgets'],
    'Dans Flutter, un widget est un élément de l’interface : un texte, un '
        'bouton, une colonne ou même un écran entier.',
    'Les widgets s’emboîtent les uns dans les autres pour former un arbre. '
        'Un widget sans état ne change pas ; un widget avec état peut se '
        'redessiner quand ses données changent.',
  ),
  Notion(
    ['api', 'une api', 'interface de programmation'],
    'Une API est un ensemble de règles qui permet à deux logiciels de '
        'communiquer : l’un envoie une demande, l’autre renvoie une réponse.',
    'Sur le Web, une API répond souvent à des requêtes HTTP en renvoyant des '
        'données au format JSON. Plus tard, JARVIS pourra utiliser une API '
        'pour se connecter à une intelligence artificielle.',
  ),
  Notion(
    ['json'],
    'Le JSON est un format de texte pour échanger des données : des paires '
        'clé et valeur, des listes, des nombres et du texte.',
    'Par exemple, accolade, guillemets nom, deux-points, guillemets Jarvis, '
        'accolade fermante. Il est lisible par un humain et facile à lire pour '
        'presque tous les langages.',
  ),
  Notion(
    ['algorithme', 'algorithmes'],
    'Un algorithme est une suite d’étapes précises pour résoudre un problème, '
        'comme une recette de cuisine.',
    'On évalue un algorithme par sa justesse et par son efficacité, c’est-à-'
        'dire le temps et la mémoire qu’il utilise quand les données '
        'grandissent. Trier une liste ou trouver un chemin sont des exemples '
        'classiques.',
  ),
  Notion(
    ['base de donnees', 'bases de donnees', 'sql'],
    'Une base de données stocke des informations de façon organisée pour '
        'pouvoir les retrouver et les modifier rapidement.',
    'Les bases relationnelles rangent les données dans des tables reliées '
        'entre elles et s’interrogent avec le langage SQL. D’autres, dites '
        'NoSQL, stockent des documents ou des paires clé-valeur.',
  ),
  Notion(
    ['python'],
    'Python est un langage de programmation simple à lire, très utilisé pour '
        'l’automatisation, l’analyse de données et l’intelligence artificielle.',
    'Il est interprété, possède une immense bibliothèque de modules, et des '
        'outils comme NumPy ou PyTorch en ont fait une référence de la science '
        'des données.',
  ),
  Notion(
    ['javascript'],
    'JavaScript est le langage qui rend les pages Web interactives. Il '
        's’exécute directement dans le navigateur.',
    'Il fonctionne aussi côté serveur avec Node.js. À ne pas confondre avec '
        'Java, qui est un langage différent.',
  ),
  Notion(
    ['git', 'github'],
    'Git est un outil qui enregistre l’historique des modifications d’un '
        'projet de code, pour revenir en arrière et travailler à plusieurs.',
    'Chaque enregistrement s’appelle un commit. Les branches permettent de '
        'développer une fonctionnalité à part avant de la fusionner. GitHub est '
        'un service en ligne qui héberge des projets Git.',
  ),
  Notion(
    ['open source', 'logiciel libre'],
    'Un logiciel open source est un logiciel dont le code est public : chacun '
        'peut le lire, le modifier et le redistribuer selon sa licence.',
    'Linux, Flutter et Firefox en sont des exemples. La licence précise ce '
        'qu’on a le droit de faire, par exemple citer l’auteur ou partager ses '
        'modifications.',
  ),

  // --- Informatique et réseaux ----------------------------------------------
  Notion(
    ['processeur', 'cpu'],
    'Le processeur, ou CPU, est le cerveau de l’ordinateur : il exécute les '
        'instructions des programmes.',
    'Sa vitesse se mesure en gigahertz, c’est-à-dire en milliards de cycles '
        'par seconde. Les processeurs modernes ont plusieurs cœurs pour '
        'travailler sur plusieurs tâches en parallèle.',
  ),
  Notion(
    ['memoire vive', 'ram'],
    'La mémoire vive, ou RAM, garde les données des programmes en cours '
        'd’utilisation. Elle est très rapide mais se vide quand on éteint '
        'l’appareil.',
    'Plus il y a de mémoire vive, plus on peut ouvrir de programmes en même '
        'temps sans ralentissement. Les fichiers, eux, sont conservés sur le '
        'disque ou le stockage.',
  ),
  Notion(
    ['carte graphique', 'gpu'],
    'La carte graphique, ou GPU, calcule les images affichées à l’écran.',
    'Elle contient des milliers de petits cœurs qui font beaucoup de calculs '
        'simples en parallèle. C’est pour cela qu’elle sert aussi à entraîner '
        'les intelligences artificielles.',
  ),
  Notion(
    ['systeme d exploitation', 'os'],
    'Le système d’exploitation est le logiciel principal d’un appareil : il '
        'gère le matériel et fait tourner les applications. Windows, Android, '
        'iOS et Linux en sont des exemples.',
    'Il s’occupe de la mémoire, des fichiers, des périphériques et de la '
        'sécurité, et il partage le processeur entre les programmes.',
  ),
  Notion(
    ['binaire', 'bit', 'octet', 'bits', 'octets'],
    'Un ordinateur ne manipule que des 0 et des 1 : c’est le binaire. Un bit '
        'vaut 0 ou 1, et un octet regroupe 8 bits.',
    'Un octet peut représenter 256 valeurs, de 0 à 255. Un kilooctet vaut '
        'mille octets, un mégaoctet un million, un gigaoctet un milliard.',
  ),
  Notion(
    ['internet'],
    'Internet est un immense réseau mondial d’ordinateurs reliés entre eux, '
        'qui échangent des données selon des règles communes appelées '
        'protocoles.',
    'Les données voyagent en petits paquets. Chaque appareil a une adresse IP, '
        'et le DNS traduit les noms de sites en adresses. Le Web n’est qu’un '
        'des services d’Internet, comme l’e-mail.',
  ),
  Notion(
    ['http', 'https'],
    'HTTP est le protocole utilisé par le Web pour demander et recevoir des '
        'pages. HTTPS est sa version chiffrée et sécurisée.',
    'Le navigateur envoie une requête, par exemple GET pour lire une page, et '
        'le serveur répond avec un code, comme 200 pour « tout va bien » ou '
        '404 pour « page introuvable ».',
  ),
  Notion(
    ['cloud', 'informatique en nuage'],
    'Le cloud, c’est utiliser des serveurs à distance, via Internet, pour '
        'stocker des données ou faire tourner des programmes, au lieu de son '
        'propre appareil.',
    'On loue la puissance dont on a besoin, quand on en a besoin. Les '
        'sauvegardes en ligne et les applications Web reposent sur le cloud.',
  ),
  Notion(
    ['chiffrement', 'cryptage', 'cryptographie'],
    'Le chiffrement transforme des données pour qu’elles soient illisibles '
        'sans la bonne clé.',
    'En chiffrement symétrique, la même clé chiffre et déchiffre. En '
        'asymétrique, une clé publique chiffre et seule la clé privée '
        'correspondante déchiffre : c’est ce qui sécurise HTTPS.',
  ),
  Notion(
    ['mot de passe', 'mots de passe'],
    'Un bon mot de passe est long, unique pour chaque site et difficile à '
        'deviner.',
    'Une phrase de passe de plusieurs mots est souvent plus sûre et plus '
        'facile à retenir qu’un mot court compliqué. Un gestionnaire de mots de '
        'passe et la double authentification renforcent encore la sécurité.',
  ),
  Notion(
    ['wifi', 'wi fi'],
    'Le Wi-Fi permet de se connecter à un réseau sans fil, grâce aux ondes '
        'radio.',
    'Il utilise surtout les bandes de 2,4 et 5 gigahertz : la première porte '
        'plus loin, la seconde est plus rapide.',
  ),
  Notion(
    ['bluetooth'],
    'Le Bluetooth relie des appareils proches sans fil, comme des écouteurs '
        'ou une montre, sur une dizaine de mètres environ.',
    'Sa version basse consommation, Bluetooth Low Energy, permet aux objets '
        'connectés de fonctionner longtemps sur une petite batterie.',
  ),
  Notion(
    ['batterie', 'batteries', 'pile', 'piles', 'accumulateur'],
    'Une batterie stocke de l’énergie sous forme chimique et la restitue '
        'sous forme d’électricité.',
    'À l’intérieur, deux électrodes sont séparées par un électrolyte. Quand '
        'l’appareil fonctionne, des ions passent de l’une à l’autre pendant '
        'que les électrons circulent dans le circuit et l’alimentent ; la '
        'recharge inverse ce mouvement. Les téléphones utilisent des '
        'batteries lithium-ion.',
  ),

  // --- JARVIS lui-même ------------------------------------------------------
  Notion(
    // Pas de nom « jarvis » : il apparaît dans trop de phrases (« bonjour
    // Jarvis »). Cette fiche répond à « comment tu fonctionnes ».
    ['ton fonctionnement', 'ta technologie'],
    'Je suis JARVIS, un assistant développé avec Flutter. J’écoute votre voix, '
        'je la transforme en texte, je cherche une réponse locale, puis je vous '
        'réponds avec une voix de synthèse.',
    'Mes réponses viennent pour l’instant de règles écrites dans '
        'l’application : l’heure et la date de votre appareil, des calculs, '
        'des explications techniques et une petite conversation. Une vraie '
        'intelligence artificielle pourra être branchée plus tard.',
  ),
];
