/*
 * Javascript processing task example. It must be installed in TaskInstaller.xml to be executed.
 * Must be implemented at least methods getName() and process(item).
 * Script tasks can access properties, extracted text and raw content of items. Based on that,
 * it can ignore items, set extra attributes or create bookmarks.
 */

function getName(){
	return "IgnoreAllButImagesAndVideos";
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
function process(e) {

     var Imagens = [ 
     		"jpeg", 
     		"jpg", 
     		"bmp", 
     		"png", 
     		"gif", 
     		"tif", 
     		"jpe", 
     		"jfif", 
     		"tiff", 
     		"webp", 
     		"heic", 
     		"wbmp", 
     		"ppm", 
     		"pgm", 
     		"pbm", 
     		"xcf", 
     		"psd"
     ];
     
     var Videos = [
     		"avi", 
     		"mp4", 
     		"mpg", 
     		"mpeg", 
     		"mov", 
     		"vob", 
     		"3gp", 
     		"flv", 
     		"wmv", 
     		"rm", 
     		"asf", 
     		"mpe", 
     		"wm", 
     		"ram", 
     		"divx", 
     		"m4v", 
     		"mkv", 
     		"m1v", 
     		"rmvb", 
     		"3gpp", 
     		"dt2", 
     		"mpv", 
     		"3g2", 
     		"mts", 
     		"qt", 
     		"webm", 
     		"m2ts", 
     		"m2v", 
     		"ff", 
     		"ogv", 
     		"f4v", 
     		"ogm", 
     		"downloading", 
     		"part", 
     		"asx", 
     		"m2t", 
     		"riff", 
     		"mod", 
     		"ts"
     ];

	// Keeps directory tree structure
     if(e.isRoot() || e.isDir())
         return;
	
     var fileExt = e.getExt();
     
     if(fileExt == null)
        fileExt = "";
      
      if(fileExt.trim().equals(""))
           e.setToIgnore(true);
           
     fileExt = fileExt.toLowerCase();
     
     // Verifica thumbs de video
     if(fileExt.indexOf("_thumb_")!=-1)
     	return;
     
     // Ignora tudo com excecao de imagens e videos
     if(Imagens.indexOf(fileExt)==-1 && Videos.indexOf(fileExt)==-1)
         e.setToIgnore(true);

}



