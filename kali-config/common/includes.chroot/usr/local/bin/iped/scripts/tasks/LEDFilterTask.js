/*
 * Javascript processing task example. It must be installed in TaskInstaller.xml to be executed.
 * Must be implemented at least methods getName() and process(item).
 * Script tasks can access properties, extracted text and raw content of items. Based on that,
 * it can ignore items, set extra attributes or create bookmarks.
 */

function getName(){
	return "LEDFilterTask";
}

function getConfigurables() {}

function init(configuration) {}

function finish(){}

/*
 * Process object "item" of EvidenceFile class. This function is executed on all case items.
 * It can access any method of EvidenceFile class:
 *
 *	Some Getters:
 *	String:  getName(), getExt(), getType(), getPath(), getHash(), getMediaType().toString(), getCategories() (categories separated by | )
 *	Date:    getModDate(), getCreationDate(), getAccessDate() (podem ser nulos)
 *  Boolean: isDeleted(), isDir(), isRoot(), isCarved(), isSubItem(), isTimedOut(), hasChildren()
 *	Long:    getLength()
 *  Metadata getMetadata()
 *  Object:  getExtraAttribute(String key) (returns an extra attribute)
 *  String:  getParsedTextCache() (returns item extracted text, if this task is placed after ParsingTask)
 *  File:    getTempFile() (returns a temp file with item content)
 *  BufferedInputStream: getBufferedInputStream() (returns an InputStream with item content)
 *
 *  Some Setters: 
 *           setToIgnore(boolean) (ignores the item and excludes it from processing and case)
 *           setAddToCase(boolean) (inserts or not item in case, after being processed: default true)
 *           addCategory(String), removeCategory(String), setMediaTypeStr(String)
 * 		 	 setExtraAttribute(key, value), setParsedTextCache(String)
 *
 */
// ============================================================================
// LISTAS DE CONFIGURAÇÃO DO LED
// ============================================================================

var Imagens = ["jpeg","jpg","bmp","png","gif","tif","jpe","jfif","tiff","webp","heic","wbmp","ppm","pgm","pbm","xcf","psd"];
var Videos = ["avi","mp4","mpg","mpeg","mov","vob","3gp","flv","wmv","rm","asf","mpe","wm","ram","divx","m4v","mkv","m1v","rmvb","3gpp","dt2","mpv","3g2","mts","qt","webm","m2ts","m2v","ff","ogv","f4v","ogm","downloading","part","asx","m2t","riff","mod","ts"];

var TermosSuspeitos = ["adolescente","angel","babies","baby","bambin","bebe","bebê","blackcat","boy","bucetinha","child","crianca","criança","cuties","cuzinho","darkcollection","daughter","defloration","fuck","funky","garotinh","gatinh","genital","girl","hairless","hentai","hurtmeh","hussyfan","hussyfun","hymen","incest","infant","jailbait","kiddie","kiddy","kids","kidzilla","kinderkutje","kingpass","kleuterkutje","liluplanet","lola","lolita","lolilust","nina","ninfet","novinh","nymph","paedo","pedo","pthc","ptsc","qqaazz","r@ygold","rape","raygold","sdpa","teen","toddler","underage","vicky","virgem","virgen","virgin","0 yo","0yo","0yr","1 yo","1yo","1yr","2 yo","2yo","2yr","3 yo","3yo","3yr","4 yo","4yo","4yr","5 yo","5yo","5yr","6 yo","6yo","6yr","7 yo","7yo","7yr","8 yo","8yo","8yr","9 yo","9yo","9yr","gigatribe","shareaza","emule","dreamule","kazaa","amule","limewire","frostwire","torbrowser","tormessenger","torchat","kdquality","kinderficker","lsbar","mafiasex","lordofthering","nablot","nimphet","pretten","opva","2jvnpygai7z6uvkw","3m2mcxyuvx7sjurh","3wkcznbshhkeaede","4jznz3kcagiqxowb","4q2lxcv26d6xjlay","6zx6cxigcq7tjtue","7mdzuqhtqzaxhxpi","7q3siksb5c6trcqo","aknsdc3jku7of5qe","auutwvpt2zktxwng","avyeyuxi2dcf4cmi","babyixntjlabwkpi","bdclubqtqy2cvso2","boysopidonajtogl","boyvidsaullbcnhu","boyvidscckevqedz","chatlistea3zbsck","childsplayboq3sq","cpvls4gi2cvvirrk","elysiumucxuu3rs2","es2adizg32j3kob5","girhkbbgsglcj4jk","gokchgwvlprblrxc","grams7enufi7jmdl","gxmrzk2s56oxzb3e","hss3uro2hsxfogfq","hurtmehpneqdprmj","hwiki2tzj277eepp","hyjmkmb3lfymiprp","jjvxrbpckwpz3kwu","m2nkhqte4sxilvre","mail2tor2zyjdctd","mailtoralnhyol5v","mkingdompdzmk7e3","mt3plrzdiyqf6jim","muff7i44irws3mwu","njwzqbbwt5wpenog","olieomd25ui2zwmu","op4jvhn65pjv3slt","opva2pilsncvtwmh","oxwugzccvk3dk6tj","pbchatkoollgzmbf","pedoartre6ookiff","pedochmilnyxthis","pedoncnkqgghgk7e","qce3tl2wr4h3g2c7","rtxoifxmiyimzp3m","saemf4erbrvhfddd","streamxxhqn3k64x","teensexaqb2wbloa","teensexixxowrrgf","tenplus547yrmxld","tlz4usfmkau5febr","tmoxh4kr5xfnvxun","torblogjp5rjeyhx","toyboxmdablekkzf","tz2u3xs63fbx4jjb","uhwikih256ynt57t","updoabb6pcii3po5","upf45jv3bziuctml","uz2tz3hgh4td6j6a","v4stwi3tzicuh6vh","wxlcwyoisgi3725u","xkinder5eseudi2h","xplayyyyyirxui4n","xqmvgskrgmuytie6","y46n5mcakffjqpzw","ybswra66ouubgzb2","ye4x7dzr6w2dpa7c","yn5u473m54dbptve","zqktlwi4fecvo6ri","jjclubumn7vkhyuw","243vnzoix3ct6vowjgakv3pdqrzkfnkoz5plwgta3ar2onqobzhz5jid","3dboys55e43kyhh6lz2ejpuhnt4fa3jifrmw3xpagivkvxn7qy5q4myd","5figq755l7c55eopjphypkpfj5b4ap5nm6rvie2tygcwtafbjhv3p3id","5hxxw4p4adget6dkbjflg2cfmktf5ojoq2sw5xyr6v4ekz6b4x56drad","alice34mdngm7dhzx34dglpactwrppd6cskewvi7ny2ktn7x7tf77qid","boysclub44b6p6ccsadvybkx5mdthrpnttaowu45l5u6ev6xe7f5c7qd","boysrusx2x57nrer4xll4ap6ityf5qskjzewhnz7s6qto3mjzegrteid","bxkqj6tqkamhrdmpsf6ehxgbqvayusionnlqc4kskaqdlvzjevwjnpid","dibocamqrholin4dzde2ul4lyiedwx4nv3zy4opg2yjixrpy7o3o3qyd","eightch55i3v3dmhtshui2x5njln3yx3ibetgbgkfghnnvctae45wrid","gdwkeoxhrj2psanwpbm3cju2yxbmry5y3ca4wrylymkfju7q5dbd76id","gk3fgh3hqpiprgl5wgazny5qsxjjzndenzpgdsd6f7z4adrxaosf4dqd","gl7qgheo7nuirnrkrmzn33wq33hmjh5p3bunrl4pskdjjtay57pniaqd","hispachcpjfymc6lhad3jsfxq2tjcpabqc5oesogvcjkvm5rjtrwtbqd","ieerjeynr5cw24xp6mme34o7mdbbtq54zssosoxnthzwpn6keqsatwqd","iifz7vplkeovyrruirnridqb6ewbvirjxkb2w333lrjeytxlt3gqbsyd","ilovecpwhugfrii2x73xcp2r4q5nxbi4xmv2uz75zljdgzj7jhidrzqd","jwzzevnbrletxx7e4nqmfv73mre7rjik6nktidduppjcei6xr75aybyd","ld2wpn4gvmw6nh722jdwpawfgcbncxkmhoftjfdpsrtkhnoqbrvb3pid","llxhfn5neym3dmsvdmu5so43lzp77i2tfoz2aasvcdjkzls3a6hz55qd","m4x46ca54hicudsmwijoxg4ds4abs6q45sr6wm6g6ptt2vbpnjxnskad","wg7ljicnzfrh7dhssrsqgiqhqe7vgzc2ovyit2zz5bgiolztieljmjyd","ygx5ek4op42ljsxcbg6jsx4k255eggn3cj65z5xkf4iei5frwvvkr6yd","z4zfh676cfnazykuwezehrz3nvcqbkqgxfy3m5qqo5hawred6moqscyd","wisefolderhider","privatefolder"];

var TermosIgnorar = ["ssdpapi","cateenrollment","angel64","angelu64","angel264","depthconvert","changelog","digirlpt","certificateencod","certificateentry","changelist","typedoc","arrangelist","trapezoid","createencrypt","mininav","stateengine","babyboynotes","babyboymain","babyboyscenes","grapes","grapefruit","notificationin","babylon","x86_angel","los_angeles"];

var ArquivosRelevantes = ["downloads.dat","library5.dat","spam.dat","createtimes.cache","fileurns.cache","limewire.props","truecrypt.exe","lockdir.exe","library1.dat","library2.dat","searches.dat","gnutella.net","tor.exe","torchat.exe","main.db","known.met","ntuser.dat","sam","security","software","system","usrclass.dat","ActivitiesCache.db"];

var PastasBuscasConteudo = ["chrome/","thunderbird/","firefox/","mozilla/","/temporary internet files/","/desktop/","/documents/","/recent/","/automaticdestinations/","/customdestinations/"];

// Exclui arquivos executáveis, ignora documentos
var ExcluirConteudo = ["exe","nexe","dll","zip","7z","xlsx","docx","pak","rar","jar","swf","swz","ico","bdic","dic","iso", "vmdk", "vhdx", "vhd", "vdi","pdf"];

// ============================================================================
// FUNÇÃO DE PROCESSAMENTO
// ============================================================================

function process(e) {
	// MODIFICAÇÃO: Preserva a estrutura de pastas e os subitens gerados a partir do conteúdo (e.isSubItem())
    if (e.isRoot() || e.isDir() || e.isSubItem()) {
        return;
    }

    var fileExt = e.getExt();
    if (fileExt == null) fileExt = "";
    fileExt = String(fileExt).toLowerCase();

    var fileName = e.getName();
    if (fileName == null) fileName = "";
    fileName = String(fileName).toLowerCase();

    var filePath = e.getPath();
    if (filePath == null) filePath = "";
    filePath = String(filePath).toLowerCase().replace(/\\/g, "/");

    // Verifica thumbs de video[cite: 1]
    if (fileExt.indexOf("_thumb_") != -1) {
        return;
    }

    var deveProcessar = false;

    // 1. Arquivo contém extensão entre as Tratadas (Apenas Imagens e Vídeos)
    if (Imagens.indexOf(fileExt) != -1 || Videos.indexOf(fileExt) != -1) {
        deveProcessar = true;
    }

    // 2. Arquivos Relevantes (Nome exato do arquivo)
    if (!deveProcessar && ArquivosRelevantes.indexOf(fileName) != -1) {
        deveProcessar = true;
    }

    // 3. Termos Suspeitos (Aplica-se a todos os arquivos, incluindo zip, rar, 7z e iso)
    if (!deveProcessar) {
        for (var i = 0; i < TermosSuspeitos.length; i++) {
            if (fileName.indexOf(TermosSuspeitos[i]) != -1) {
                var ehFalsoPositivo = false;
                for (var j = 0; j < TermosIgnorar.length; j++) {
                    if (fileName.indexOf(TermosIgnorar[j]) != -1) {
                        ehFalsoPositivo = true;
                        break;
                    }
                }
                
                if (!ehFalsoPositivo) {
                    deveProcessar = true;
                    break;
                }
            }
        }
    }

    // 4. Pastas para Busca de Conteúdo
    if (!deveProcessar) {
        var dentroDaPastaAlvo = false;
        for (var i = 0; i < PastasBuscasConteudo.length; i++) {
            if (filePath.indexOf(PastasBuscasConteudo[i]) != -1) {
                dentroDaPastaAlvo = true;
                break;
            }
        }
        
        // Se estiver na pasta alvo, verifica se não está na lista de exclusão (que agora abrange os compactados)
        if (dentroDaPastaAlvo && ExcluirConteudo.indexOf(fileExt) == -1) {
            deveProcessar = true;
        }
    }

    // Ignora o arquivo caso ele não passe em nenhuma das condições acima[cite: 1]
    if (!deveProcessar) {
        e.setToIgnore(true);
    }
}