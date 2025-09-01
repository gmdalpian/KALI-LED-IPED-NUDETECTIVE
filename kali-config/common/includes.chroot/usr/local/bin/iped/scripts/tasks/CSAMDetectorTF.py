import traceback
import io
import os
import time
import sys
import threading
from collections import deque
from java.lang import System
from java.lang import Thread

# Suppresses TensorFlow log messages for a cleaner console.
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '2'

# Loads TensorFlow library only when task is enabled, 
# to avoid delays and compatibilty problems when not in use
tf = None
keras = None

CSAM_ENABLEPROP = 'enableCSAMDetectorTF'
CSAM_MODELFILE = 'classificador_imagens_v2.keras'
CSAM_SCORE = 'csam_score'
CSAM_IMG_SIZE = 224
CSAM_ENABLED = False
CSAM_SEMAPHORE = None
# Number of images or video frames to be processed at the same time
CSAM_BATCH_SIZE = 64

def loadModel():
    
    model = caseData.getCaseObject('csam_model')
    if model is None:
        file = System.getProperty('iped.root') +  '/models/' + CSAM_MODELFILE
        from keras.models import load_model        
        try:
            logger.info(f"Carregando modelo de Detecção de CSAM (TensorFlow) de: {file}")
            model = load_model(file)
            logger.info("Modelo carregado com sucesso.")
        except Exception as e:
            logger.warn(f"ERRO FATAL: Nao foi possivel carregar o modelo em {file}. Erro: {e}")
            return None     
        
        caseData.putCaseObject('csam_model', model)

        from java.util.concurrent import ConcurrentHashMap
        cache = ConcurrentHashMap()
        caseData.putCaseObject('csam_score_cache', cache)
    
    return model

def createSemaphore():
    global CSAM_SEMAPHORE
    CSAM_SEMAPHORE = caseData.getCaseObject('CSAM_SEMAPHORE')
    if(CSAM_SEMAPHORE is None):
        from java.util.concurrent import Semaphore
        CSAM_SEMAPHORE = Semaphore(1)
        caseData.putCaseObject('CSAM_SEMAPHORE', CSAM_SEMAPHORE)
    return CSAM_SEMAPHORE
   
def isImage(item):
    return item.getMediaType() is not None and item.getMediaType().toString().startswith('image')
       
# def isSupportedVideo(item):
    # return item.getMediaType() is not None and item.getMediaType().toString().startswith('video') and item.getViewFile() is not None
    
def supported(item):
    supported = (
        item.getLength() is not None and
        item.getLength() > 0 and
        isImage(item) and
        item.getExtraAttribute('hasThumb') and
        item.getHash() is not None
    )
    return supported 

def convertJavaByteArray(byteArray):
    result =  bytes(b % 256 for b in byteArray)
    return result
    
def processar_bytes_de_imagem_tf(image_bytes):
    """Pré-processa um array de bytes de imagem para o modelo."""
    img = tf.io.decode_image(image_bytes, channels=3, expand_animations=False)
    img = tf.image.resize(img, [CSAM_IMG_SIZE, CSAM_IMG_SIZE])
    return img
    
def carregar_e_processar_imagem_tf(caminho_arquivo):
    img = tf.io.read_file(caminho_arquivo)
    img = processar_bytes_de_imagem_tf(img)
    return img    
    
def carregar_e_processar_imagem(item):
    img_bytes = None
    
    if(item.isQueueEnd()):
        return None

    if item.getViewFile() is not None and os.path.exists(item.getViewFile().getAbsolutePath()):
        img_path = item.getViewFile().getAbsolutePath()
    else:
        img_path = item.getTempFile().getAbsolutePath()                

    try:       
        img_bytes = carregar_e_processar_imagem_tf(img_path)
    except Exception as e:
        # in case of image decoding error by tensorflow tries to load only iped thumbnail
        logger.warn(f"Error loading image {item.getPath()}, trying to load only thumbnail: {e}")
        if(item.getThumb() is not None):
            img_bytes = processar_bytes_de_imagem_tf(convertJavaByteArray(item.getThumb()));

    return img_bytes  
   
def processImages(itemList, tensors):
    preds = makePrediction(tensors)
    cache = caseData.getCaseObject('csam_score_cache')
    for i in range(len(itemList)):
        score = extrair_e_formatar_dois_digitos(preds[i][0])
        itemList[i].setExtraAttribute(CSAM_SCORE, score)
        cache.put(itemList[i].getHash(), score)
        
def extrair_e_formatar_dois_digitos(score):
  """
  Extrai os dois dígitos inteiros antes da vírgula.
  Se o resultado for menor que 10, preenche com um zero à esquerda.
  """
  numero = score*100

  # Trata o caso em que o score é 100%, reduzindo para 99 para ficar em dois digitos
  if(numero==100):
      return "99"
      
  # Isola a parte do número (ex: 123.45 -> 23.45)
  numero_reduzido = numero % 100
  
  # Remove a parte decimal, sem arredondar (ex: 23.45 -> 23)
  parte_inteira = int(numero_reduzido)
  
  # Formata para ter sempre 2 dígitos, preenchendo com 0 se necessário
  return f'{parte_inteira:02d}'        

def makePrediction(image_tensors):
  
    model = loadModel()
    try:
        if CSAM_SEMAPHORE is not None:
            CSAM_SEMAPHORE.acquire()

        image_batch_tensor = tf.stack(image_tensors)
        predictions = model.predict(image_batch_tensor, verbose=0)
        return predictions
    finally:
        if CSAM_SEMAPHORE is not None:
            CSAM_SEMAPHORE.release()    
    
'''
Main class
'''
class CSAMDetectorTF:
       
    def __init__(self):        
        # List to accumulate items until a batch is formed
        self.itemList = []
        self.imageBytes = []
        # Queue for ALL items (single or batched) ready to be sent
        self.itemsToSend = deque()
        self.BATCH_LOCK = threading.Lock()
        
    def isEnabled(self):
        return CSAM_ENABLED

    def processQueueEnd(self):
        return True
       
    def getConfigurables(self):
        from iped.engine.config import EnableTaskProperty
        return [EnableTaskProperty(CSAM_ENABLEPROP)]
        
    
    def init(self, configuration):
        global CSAM_ENABLED, tf, keras
        CSAM_ENABLED = configuration.getEnableTaskProperty(CSAM_ENABLEPROP)
        if not CSAM_ENABLED:
            return
        
        # TensorFlow Lazy Loading
        if tf is None:
            logger.info("CSAMDetectorTF está habilitado. Carregando TensorFlow...")
            os.environ['TF_CPP_MIN_LOG_LEVEL'] = '2'
            import tensorflow
            from tensorflow import keras as keras_module
            tf = tensorflow
            keras = keras_module
            logger.info("TensorFlow carregado com sucesso.")
        
        from iped.engine.config import HashTaskConfig
        from iped.engine.config import ImageThumbTaskConfig 
        from iped.engine.config import VideoThumbsConfig
        
        hashConfig = configuration.findObject(HashTaskConfig).isEnabled()
        imageThumbsConfig = configuration.findObject(ImageThumbTaskConfig).isEnabled()
        videoThumbsConfig = configuration.findObject(VideoThumbsConfig).isEnabled()
        videoThumbsSubitems = configuration.findObject(VideoThumbsConfig).getVideoThumbsSubitems()
        
        requiredTasks = (
            hashConfig and
            imageThumbsConfig and
            videoThumbsConfig and
            videoThumbsSubitems
        )

        if not requiredTasks:
            logger.warn(
                "Para usar o CSAMDetectorTF as seguintes funcoes tambem devem ser ativadas: "
                "enableHash enableImageThumbs enableVideoThumbs enableVideoThumbsSubitems"
            )
            CSAM_ENABLED = False
            return

        loadModel()
        createSemaphore() 
       
    def process(self, item):
        
        # Stores the logic to determine if this item should be added to processing batch
        add_to_batch = True
        
        # Queue end or not supported item
        if item.isQueueEnd() or not supported(item):
            add_to_batch = False
                                
        # don't process it again (in the report generation for example)
        csamscore = item.getExtraAttribute(CSAM_SCORE)
        if csamscore is not None:
            add_to_batch = False
        
        if item.getHash() is not None:
            cache = caseData.getCaseObject('csam_score_cache')
            score = cache.get(item.getHash())
            if score is not None:
                logger.debug(f"CSAMDetectorTF: worker {self.worker.id} found previous score for item {item.getName()} {score}")
                item.setExtraAttribute(CSAM_SCORE, score)                
                add_to_batch = False                  
        
        img_tensor = None
        # Tries to load image bytes
        if(add_to_batch):
            img_tensor = carregar_e_processar_imagem(item)         
            if img_tensor is None:    
                item.setExtraAttribute('csam_error', 1)
                logger.error(f"CSAMDetectorTF: worker {self.worker.id} thumb error on item: {item.getName()}, id {item.getId()}")
                add_to_batch = False  
        
                    
        """
        Acts as a dispatcher: decides if an item should be batched or
        sent directly. All items destined for the next task are placed
        in the itemsToSend queue.
        """
        with self.BATCH_LOCK:
            # Step 1: Classify the incoming item.
            # If supported, add to the batch list. Otherwise, add directly to the send queue.
            if add_to_batch:
                self.itemList.append(item)
                self.imageBytes.append(img_tensor)
            else:
                self.itemsToSend.append(item)

            # Step 2: Check if the batch needs to be flushed.
            # This happens if the batch is full, or if the end of the queue is signaled.
            if (len(self.itemList) >= CSAM_BATCH_SIZE or item.isQueueEnd()) and self.itemList:
                # The batch is ready, process it before sending.
                logger.debug(f"CSAMDetectorTF: worker {self.worker.id} processing batch of {len(self.itemList)} items.")
                processImages(self.itemList, self.imageBytes)
                
                # Move the now-processed items to the sending queue.
                self.itemsToSend.extend(self.itemList)
                self.itemList.clear()
                self.imageBytes.clear()

                       
    def sendToNextTask(self, item):                
        """
        Acts as a simple sender. It drains the itemsToSend queue and sends
        everything that the process() method has prepared. The 'item'

        parameter is no longer needed for the logic itself.
        """
        items_to_send_now = deque()

        with self.BATCH_LOCK:
            # Drains the output queue to a local variable for sending.
            while self.itemsToSend:
                items_to_send_now.append(self.itemsToSend.popleft())

        # Sends all items that were ready.
        # This is done outside the lock.
        while items_to_send_now:
            self.javaTask.sendToNextTaskSuper(items_to_send_now.popleft())
        
            
    def finish(self):
        
        # global bookmarkCreated
        
        # if(not bookmarkCreated):
            # #Cria o Bookmark
            # query = CSAM_SCORE + ">" + str(POSITIVE_THRESHOLD)
        
            # #set query into searcher
            # searcher.setQuery(query)
        
            # #search in case and return item ids
            # ids = searcher.search().getIds()
        
            # if(ids):
                # logger.info("Criando bookmark CSAM")
                # #create new bookmark and get its id
                # bookmarkId = ipedCase.getBookmarks().newBookmark("Possivel CSAM (IA)")
        
                # #set bookmark comment
                # ipedCase.getBookmarks().setBookmarkComment(bookmarkId, "Arquivos possivelmente contendo cenas de abuso sexual infantil, detectador por Inteligencia Artificial. Pode gerar muitos falsos positivos.")
        
                # #add item ids to created bookmark
                # ipedCase.getBookmarks().addBookmark(ids, bookmarkId)
        
                # #save changes synchronously
                # ipedCase.getBookmarks().saveState(True)                
            # else:
                # logger.info("Nenhuma CSAM detectada")
                
            # bookmarkCreated = True
        
        logger.info(f"{Thread.currentThread().getName()}: Análise de CSAM finalizada.")
        return True 