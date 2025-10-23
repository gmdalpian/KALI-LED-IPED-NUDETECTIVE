"""
IPED task to detect Child Sexual Abuse Material (CSAM) using a TensorFlow or PyTorch based AI model.

The script must be enabled in IPED, and related PIP packages must be installed (tensorflow or torch, torchvision, timm, pillow).

On Linux, you need to install jep (pip install jep) and include jep.so in LD_LIBRARY_PATH.
see https://github.com/sepinf-inc/IPED/wiki/User-Manual#python-modules
"""

__author__ = "Guilherme Dalpian"
__email__ = "gmdalpian@gmail.com"
__version__ = "0.6"

import traceback
import io
import os
import time
import sys
from java.lang import System
from iped.engine.task import HashDBLookupTask
from java.awt import Color
import numpy as np

# --- Placeholders for Late Loading ---
tf = None
tflite = None
keras = None
torch = None
nn = None
timm = None
transforms = None
Image = None

# --- Global Configurations ---
PLUGIN_ENABLE_PROP = 'enableCSAMDetector'
CSAM_CONFIG_FILE = 'CSAMDetectorConfig.txt'
CSAM_SCORE = 'csam_score'
PORN_SCORE = 'porn_score'
MODEL_SEMAPHORE = None
CSAM_IMG_SIZE = 224

# --- Global Control Variables ---
MOTOR_IA = None
MODELO_CARREGADO = None
DEVICE = None
CACHE = None
CLASS_NAMES = ['csam', 'porn', 'other']
NUM_CLASSES = len(CLASS_NAMES)

# Configurable parameters defaults
PLUGIN_ENABLED = False
CSAM_MODELFILE = 'tensorflow_b0_v1.keras'
CSAM_BATCH_SIZE = 64
CSAM_MINIMUM_IMAGE_SIZE = 0  # in bytes
CSAM_SKIP_DIMENSION = 0  # in pixels
CSAM_SKIP_HASHDB_FILES = 'false'  # skip files with hits on IPED HashDB database
CSAM_CREATE_BOOKMARKS = 'false'

CSAM_MODELFILE_PROPERTY = 'CSAMModelFile'
CSAM_BATCH_SIZE_PROPERTY = 'CSAMBatchSize'
CSAM_MINIMUM_IMAGE_SIZE_PROPERTY = 'CSAMMinimumImageSize'
CSAM_SKIP_DIMENSION_PROPERTY = 'CSAMSkipDimension'
CSAM_SKIP_HASHDB_FILES_PROPERTY = 'CSAMSkipHashDBFiles'
CSAM_CREATE_BOOKMARKS_PROPERTY = 'CSAMCreateBookmarks'

# AI constants
AI_CLASSIFICATION_SKIP_ATTR = "AIClassificationSkip"
AI_CLASSIFICATION_SKIP_NO = "no"
AI_CLASSIFICATION_SKIP_SIZE = "size"
AI_CLASSIFICATION_SKIP_DIMENSION = "dimension"
AI_CLASSIFICATION_SKIP_HASHDB = "hashDB"
AI_CLASSIFICATION_SKIP_DUPLICATE = "duplicate"

# =============================================================================
# LOADING AND PREDICTION LOGIC (UNIFIED)
# =============================================================================

def carregar_e_configurar_modelo():
    """Central function that loads the correct model (TF or PyTorch) and sets parameters."""
    global MODELO_CARREGADO, DEVICE, CACHE, CSAM_IMG_SIZE
    
    MODELO_CARREGADO = caseData.getCaseObject('csam_model_unificado')
    if MODELO_CARREGADO is None:
        caminho_modelo = System.getProperty('iped.root') + '/models/' + CSAM_MODELFILE
        if not os.path.exists(caminho_modelo):
            logger.warn(f"FATAL ERROR: Model file not found: {caminho_modelo}")
            return None

        nome_modelo_lower = CSAM_MODELFILE.lower()
        if "_s_" in nome_modelo_lower:
            CSAM_IMG_SIZE = 384
        elif "_m_" in nome_modelo_lower or "_l_" in nome_modelo_lower:
            CSAM_IMG_SIZE = 480
        else: # Default for B0
            CSAM_IMG_SIZE = 224
        logger.info(f"Image size set to {CSAM_IMG_SIZE}x{CSAM_IMG_SIZE} based on model name.")

        if MOTOR_IA == 'tensorflow':
            try:
                logger.info(f"Loading TensorFlow model from: {caminho_modelo}")
                MODELO_CARREGADO = keras.models.load_model(caminho_modelo)
                logger.info("TensorFlow model loaded successfully.")
            except Exception as e:
                logger.warn(f"FATAL ERROR loading TensorFlow model: {e}")
                return None
        
        elif MOTOR_IA == 'pytorch':
            try:
                logger.info(f"Loading PyTorch model from: {caminho_modelo}")
                DEVICE = torch.device("cuda:0" if torch.cuda.is_available() else "cpu")
                
                modelo_timm = 'tf_efficientnetv2_b0'
                if "_s_" in nome_modelo_lower: modelo_timm = 'tf_efficientnetv2_s.in21k'
                elif "_m_" in nome_modelo_lower: modelo_timm = 'tf_efficientnetv2_m.in21k'
                elif "_l_" in nome_modelo_lower: modelo_timm = 'tf_efficientnetv2_l.in21k'
                
                MODELO_CARREGADO = timm.create_model(modelo_timm, pretrained=False, num_classes=NUM_CLASSES)
                state_dict = torch.load(caminho_modelo, map_location=DEVICE)
                MODELO_CARREGADO.load_state_dict(state_dict)
                MODELO_CARREGADO.to(DEVICE)
                MODELO_CARREGADO.eval()
                logger.info(f"PyTorch model loaded successfully on device: {DEVICE}")
            except Exception as e:
                logger.warn(f"FATAL ERROR loading PyTorch model: {e}")
                return None
                
        elif MOTOR_IA == 'tflite': 
            try:
                logger.info(f"Loading TFLite model from: {caminho_modelo}")                
                MODELO_CARREGADO = tflite.Interpreter(model_path=caminho_modelo)
                input_details = MODELO_CARREGADO.get_input_details()[0]
                output_details = MODELO_CARREGADO.get_output_details()[0]
    
                input_details = MODELO_CARREGADO.get_input_details()[0]
                CSAM_IMG_SIZE = input_details['shape'][1]
                input_dtype = input_details['dtype']
                is_quantized = input_dtype == np.int8

                logger.info(f"Modelo espera imagens de tamanho: {CSAM_IMG_SIZE}x{CSAM_IMG_SIZE}")
                
                if is_quantized:
                    logger.info("Modelo quantizado (INT8) detectado.")                
                logger.info("TFLite model loaded successfully.")
            except Exception as e:
                logger.warn(f"FATAL ERROR loading TFLite model: {e}")
                return None            
        
        caseData.putCaseObject('csam_model_unificado', MODELO_CARREGADO)
        
    return MODELO_CARREGADO

def processar_imagem(item):
    """Loads and preprocesses the image to the correct format (tensor)."""
    try:
        file_path = None
        if item.getViewFile() is not None and os.path.exists(item.getViewFile().getAbsolutePath()):
            file_path = item.getViewFile().getAbsolutePath()
        else:
            file_path = item.getTempFile().getAbsolutePath()  
            item.getTempFile().getAbsolutePath()

        if not os.path.exists(file_path):
            raise IOError("Temporary file not found")

        if MOTOR_IA == 'tensorflow' or MOTOR_IA == 'tflite':
            img = tf.io.read_file(file_path)
            img = tf.io.decode_image(img, channels=3, expand_animations=False)
            return tf.image.resize(img, [CSAM_IMG_SIZE, CSAM_IMG_SIZE])

        elif MOTOR_IA == 'pytorch':
            image = Image.open(file_path).convert('RGB')
            transform = transforms.Compose([
                transforms.Resize((CSAM_IMG_SIZE, CSAM_IMG_SIZE)), transforms.ToTensor(),
                transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])])
            return transform(image)                     
            
    except Exception as e:
        logger.warn(f"Error processing image {item.getPath()}, trying thumbnail... {e}")
        try:
            image_bytes = bytes(b % 256 for b in item.getThumb())
            if MOTOR_IA == 'tensorflow' or MOTOR_IA == 'tflite':
                img = tf.io.decode_image(image_bytes, channels=3, expand_animations=False)
                return tf.image.resize(img, [CSAM_IMG_SIZE, CSAM_IMG_SIZE])
            elif MOTOR_IA == 'pytorch':
                image = Image.open(io.BytesIO(image_bytes)).convert('RGB')
                transform = transforms.Compose([
                    transforms.Resize((CSAM_IMG_SIZE, CSAM_IMG_SIZE)), transforms.ToTensor(),
                    transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])])
                return transform(image)
        except Exception as thumb_e:
            logger.error(f"Failed to process thumbnail for {item.getPath()}: {thumb_e}")
            return None

def createSemaphore():
    global MODEL_SEMAPHORE
    MODEL_SEMAPHORE = caseData.getCaseObject('CSAM_SEMAPHORE')
    if(MODEL_SEMAPHORE is None):
        from java.util.concurrent import Semaphore
        MODEL_SEMAPHORE = Semaphore(1)
        caseData.putCaseObject('CSAM_SEMAPHORE', MODEL_SEMAPHORE)
    return MODEL_SEMAPHORE
    
def extrair_e_formatar_dois_digitos(score):
  numero = score*100
  if numero >= 100: return "99"      
  return f'{int(numero):02d}' 

def isImage(item):
    return item.getMediaType() is not None and item.getMediaType().toString().startswith('image')

def supported(item):
    supported = (
        item.getLength() is not None and
        item.getLength() > 0 and
        isImage(item) and
        item.getExtraAttribute('hasThumb') and
        item.getHash() is not None
    )
    return supported
    
'''
Main class
'''
class CSAMDetector:
    def __init__(self):
        self.itemList = []
        self.imageBytes = []
        modelo_tflite = None

    def isEnabled(self):
        return PLUGIN_ENABLED

    def processQueueEnd(self):
        return True
       
    def getConfigurables(self):
        from iped.engine.config import DefaultTaskPropertiesConfig
        return [DefaultTaskPropertiesConfig(PLUGIN_ENABLE_PROP, CSAM_CONFIG_FILE)]        

    def init(self, configuration):
        global PLUGIN_ENABLED, MOTOR_IA, CSAM_MODELFILE, CACHE, CSAM_BATCH_SIZE, CSAM_MINIMUM_IMAGE_SIZE, CSAM_SKIP_DIMENSION, CSAM_SKIP_HASHDB_FILES, tf, keras, torch, nn, timm, transforms, Image, tflite
        
        taskConfig = configuration.getTaskConfigurable(CSAM_CONFIG_FILE)
        PLUGIN_ENABLED = taskConfig.isEnabled()

        if not PLUGIN_ENABLED:
            return
        
        extraProps = taskConfig.getConfiguration()
        
        if(extraProps):
            CSAM_MODELFILE = extraProps.getProperty(CSAM_MODELFILE_PROPERTY) if extraProps.getProperty(CSAM_MODELFILE_PROPERTY) is not None else CSAM_MODELFILE
            CSAM_BATCH_SIZE = int(extraProps.getProperty(CSAM_BATCH_SIZE_PROPERTY)) if extraProps.getProperty(CSAM_BATCH_SIZE_PROPERTY) is not None else CSAM_BATCH_SIZE
            CSAM_MINIMUM_IMAGE_SIZE = int(extraProps.getProperty(CSAM_MINIMUM_IMAGE_SIZE_PROPERTY)) if extraProps.getProperty(CSAM_MINIMUM_IMAGE_SIZE_PROPERTY) is not None else CSAM_MINIMUM_IMAGE_SIZE
            CSAM_SKIP_DIMENSION = int(extraProps.getProperty(CSAM_SKIP_DIMENSION_PROPERTY)) if extraProps.getProperty(CSAM_SKIP_DIMENSION_PROPERTY) is not None else CSAM_SKIP_DIMENSION
            skipDBFiles = extraProps.getProperty(CSAM_SKIP_HASHDB_FILES_PROPERTY) if extraProps.getProperty(CSAM_SKIP_HASHDB_FILES_PROPERTY) is not None else CSAM_SKIP_HASHDB_FILES
            CSAM_SKIP_HASHDB_FILES = True if skipDBFiles.lower() == 'true' else False
            createbookmarks = extraProps.getProperty(CSAM_CREATE_BOOKMARKS_PROPERTY) if extraProps.getProperty(CSAM_CREATE_BOOKMARKS_PROPERTY) is not None else CSAM_CREATE_BOOKMARKS
            CSAM_CREATE_BOOKMARKS = True if createbookmarks.lower() == 'true' else False
            
        
        logger.debug(f"CSAM configurations: {CSAM_MODELFILE} {CSAM_BATCH_SIZE} {CSAM_MINIMUM_IMAGE_SIZE} {CSAM_SKIP_DIMENSION} {CSAM_SKIP_HASHDB_FILES}")
        
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
                "To use CSAMDetector the following functions must also be enabled: "
                "enableHash enableImageThumbs enableVideoThumbs enableVideoThumbsSubitems"
            )
            PLUGIN_ENABLED = False
            return  
           
        model_name_lower = CSAM_MODELFILE.lower()           
        if model_name_lower.startswith('tensorflow') or model_name_lower.endswith('.keras'):
            MOTOR_IA = 'tensorflow'
            if tf is None:
                logger.info("TensorFlow engine detected. Loading libraries...")
                os.environ['TF_CPP_MIN_LOG_LEVEL'] = '3'
                import tensorflow as tf_module
                from tensorflow import keras as keras_module
                tf = tf_module
                keras = keras_module
                logger.info("TensorFlow libraries loaded.")
        
        elif model_name_lower.startswith('pytorch') or model_name_lower.endswith('.pt'):
            MOTOR_IA = 'pytorch'
            if torch is None:
                logger.info("PyTorch engine detected. Loading libraries...")
                import torch as torch_module
                import torch.nn as nn_module
                from torchvision import transforms as transforms_module
                import timm as timm_module
                from PIL import Image as Image_module
                torch = torch_module
                nn = nn_module
                timm = timm_module
                transforms = transforms_module
                Image = Image_module
                logger.info("PyTorch libraries loaded.")
        elif model_name_lower.startswith('tflite') or model_name_lower.endswith('.tflite'):      
            MOTOR_IA = 'tflite'
            if tflite is None:
                logger.info("TFLite engine detected. Loading libraries...")
                os.environ['TF_CPP_MIN_LOG_LEVEL'] = '3'
                # Tenta importar o interpretador leve primeiro, se falhar, usa o do TF completo
                import tensorflow as tf_module
                tf = tf_module
                tflite = tf.lite
                logger.info("Using TFLite from full TensorFlow package.")
        else:
            logger.warn(f"ERROR: Could not determine AI engine from model name: {CSAM_MODELFILE}")
            PLUGIN_ENABLED = False
            return

        if not carregar_e_configurar_modelo():
             PLUGIN_ENABLED = False
             return
             
        if(not CACHE):
            from java.util.concurrent import ConcurrentHashMap
            CACHE = ConcurrentHashMap()
            caseData.putCaseObject('csam_cache_unificado', CACHE)             
    
        # In case of TFLite model, each thread must have its own interpreter for the model
        if MOTOR_IA == 'tflite':
            caminho_modelo = System.getProperty('iped.root') + '/models/' + CSAM_MODELFILE
            self.modelo_tflite = tf.lite.Interpreter(model_path=caminho_modelo)
            self.modelo_tflite.allocate_tensors()
            CSAM_BATCH_SIZE = 1
        else:
            # semaphore is only used when processing in batches, tflite is multithreaded
            createSemaphore()

    def process(self, item):
        
        logger.debug(f"CSAMDetector: called process for item {item.getPath()} {item.getId()}")
        
        if not item.isQueueEnd() and not supported(item):
            return

        # don't process it again (in the report generation for example)
        csamscore = item.getExtraAttribute(CSAM_SCORE)
        if csamscore is not None:
            return                      
        
        # Skip very small images in bytes
        if item.getLength() is not None and item.getLength() < CSAM_MINIMUM_IMAGE_SIZE:                
            logger.debug(f"CSAMDetector: skipping very small image {item.getName()} {item.getLength()} bytes")
            item.setExtraAttribute(AI_CLASSIFICATION_SKIP_ATTR, AI_CLASSIFICATION_SKIP_SIZE)                
            return

        # Skip very small dimensions
        if(CSAM_SKIP_DIMENSION>0):
            if(isImage(item)):
                width_meta = item.getMetadata().get("image:Width")
                height_meta = item.getMetadata().get("image:Height")
                width = int(width_meta) if width_meta is not None else None
                height = int(height_meta) if height_meta is not None else None
                if(width is not None and height is not None and (width<CSAM_SKIP_DIMENSION or height<CSAM_SKIP_DIMENSION)):
                    logger.debug(f"CSAMDetector: skipping very small image {item.getName()} {width}x{height}")
                    item.setExtraAttribute(AI_CLASSIFICATION_SKIP_ATTR, AI_CLASSIFICATION_SKIP_DIMENSION)
                    return

        # Skip classification of images/videos with hits on IPED hashesDB database (see 'skipHashDBFiles' config property)
        if (CSAM_SKIP_HASHDB_FILES and item.getExtraAttribute(HashDBLookupTask.STATUS_ATTRIBUTE) is not None):
            logger.debug(f"CSAMDetector: skipping item with HashDB hit {item.getName()}")
            item.setExtraAttribute(AI_CLASSIFICATION_SKIP_ATTR, AI_CLASSIFICATION_SKIP_HASHDB)
            return
        
        if item.getHash():
            cache = caseData.getCaseObject('csam_cache_unificado')
            scores = cache.get(item.getHash())
            if scores is not None:
                try:
                    csam_score, porn_score = scores
                    logger.debug(f"CSAMDetector: Found cached scores for {item.getName()}: csam={csam_score}, porn={porn_score}")
                    item.setExtraAttribute(CSAM_SCORE, csam_score)
                    item.setExtraAttribute(PORN_SCORE, porn_score)
                    item.setExtraAttribute(AI_CLASSIFICATION_SKIP_ATTR, AI_CLASSIFICATION_SKIP_DUPLICATE)
                    return
                except (TypeError, ValueError):
                     logger.warn(f"CSAMDetector: Outdated cache format for hash {item.getHash()}. Reprocessing.")

        img_tensor = None
        
        if(not item.isQueueEnd()):
            img_tensor = processar_imagem(item)            
            if img_tensor is None:    
                item.setExtraAttribute('csam_error', 1)
                logger.error(f"CSAMDetector: error processing image: {item.getName()}, id {item.getId()}")
                return
            
            self.itemList.append(item)
            self.imageBytes.append(img_tensor)

        # Check if the batch needs to be flushed.
        # This happens if the batch is full, or if the end of the queue is signaled.
        if (self.isToProcessBatch(item)):
            logger.debug(f"CSAMDetector: processing batch of {len(self.itemList)} items.")
            self.processar_lote_de_imagens(self.itemList, self.imageBytes)


    def sendToNextTask(self, item):       
       
        isItemOnList = False
        
        # Checks if the item is in the list to be processed (e.g., not an image or queueend)
        if item in self.itemList:
            isItemOnList = True
    
        # Now we check if we just processed a batch, to clear the list and send everything to the next task
        if self.isToProcessBatch(item):                 
            for i in self.itemList:
                javaTask.get().sendToNextTaskSuper(i) 
            self.itemList.clear()
            self.imageBytes.clear()
            
        # If the item is not on the list, send it to the next task.
        if(not isItemOnList):
            javaTask.get().sendToNextTaskSuper(item) 


    def isToProcessBatch(self, item):
        size = len(self.itemList)
        return size >= CSAM_BATCH_SIZE or (size > 0 and item.isQueueEnd())    


    def finish(self):              
        global CSAM_CREATE_BOOKMARKS
        
        logger.debug("CSAMDetector: CSAM analysis finished.")                
        
        if not CSAM_CREATE_BOOKMARKS:
            return

        CSAM_CREATE_BOOKMARKS = False
        
        bookmarks_to_create = [
            {
                "query": "csam_score:[85 TO *]",
                "name": "Possible CSAM IA - 1 - Higher Confidence",
                "comment": "Possible CSAM files, high confidence",
                "color": [220, 20, 60]
            },
            {
                "query": "csam_score:[60 TO 84]",
                "name": "Possible CSAM IA - 2 - Medium Confidence",
                "comment": "Possible CSAM files, medium confidence",
                "color": [255, 165, 0]
            },
            {
                "query": "csam_score:[40 TO 59]",
                "name": "Possible CSAM IA - 3 - Low Confidence",
                "comment": "Possible CSAM files, low confidence",
                "color": [255, 255, 0]
            },
            {
                "query": "porn_score>50",
                "name": "Probable Adult Porn (IA)",
                "comment": "Probable Porn files, for manual review",
                "color": [255, 105, 180]
            },
            {
                "query": "hashDb\:status:pedo",
                "name": "Probable CSAM - Hash Hit",
                "comment": "Probable CSAM - hash hit",
                "color": [255, 0, 0]
            }
        ]  

        # Itera sobre a lista e chama a função para cada item
        for bookmark_data in bookmarks_to_create:
            self.create_bookmark_from_query(
                query=bookmark_data["query"], 
                bookmark_name=bookmark_data["name"], 
                bookmark_comment=bookmark_data["comment"],
                color=bookmark_data["color"]
            )      
        
        return True
        
    def create_bookmark_from_query(self, query, bookmark_name, bookmark_comment, color):
        """
        Executa uma busca e, se encontrar resultados, cria um bookmark com eles.

        Args:
            query (str): A string de consulta para a busca.
            bookmark_name (str): O nome do bookmark a ser criado.
            bookmark_comment (str): O comentário para o bookmark.
        """
        
        # Define e executa a consulta
        searcher.setQuery(query)
        ids = searcher.search().getIds()
        
        # Cria o bookmark mesmo que vazio
        bookmarks = ipedCase.getBookmarks()
        bookmark_id = bookmarks.newBookmark(bookmark_name)
        bookmarks.setBookmarkComment(bookmark_id, bookmark_comment)
        if(color):
            bookmarks.setBookmarkColor(bookmark_id, Color(color[0], color[1], color[2]))        
        
        # Verifica se houve resultados
        if ids and len(ids) > 0:
            # Cria e configura o novo bookmark
            bookmarks.addBookmark(ids, bookmark_id)

        # Salva as alterações
        bookmarks.saveState(True)       
        
       
    def fazer_predicao(self, tensores):
        """Runs batch prediction, returning the full probability array."""
        global MODEL_SEMAPHORE, MOTOR_IA, DEVICE, MODELO_CARREGADO
        try:
            if MODEL_SEMAPHORE is not None:
                MODEL_SEMAPHORE.acquire()
            
            if MOTOR_IA == 'tensorflow':
                return MODELO_CARREGADO.predict(tf.stack(tensores), verbose=0)
            
            elif MOTOR_IA == 'pytorch':
                with torch.no_grad():
                    outputs = MODELO_CARREGADO(torch.stack(tensores).to(DEVICE))
                    return torch.nn.functional.softmax(outputs, dim=1).cpu().numpy()
            
            elif MOTOR_IA == 'tflite':                
                interpreter = self.modelo_tflite
                input_details = interpreter.get_input_details()[0]
                output_details = interpreter.get_output_details()[0]
                is_quantized = input_details['dtype'] == np.int8
                
                predictions = []
                for tensor in tensores:
                    input_tensor = np.expand_dims(tensor.numpy(), axis=0)
                    
                    if is_quantized:
                        input_tensor = (input_tensor.astype(np.float32) - 128).astype(np.int8)

                    interpreter.set_tensor(input_details['index'], input_tensor)
                    interpreter.invoke()
                    output_data = interpreter.get_tensor(output_details['index'])
                    
                    if is_quantized:
                        scale, zero_point = output_details['quantization']
                        output_data = (output_data.astype(np.float32) - zero_point) * scale

                    predictions.append(output_data[0])
                
                return np.array(predictions)

                
        finally:
            if MODEL_SEMAPHORE is not None:
                MODEL_SEMAPHORE.release()

    def processar_lote_de_imagens(self, items, tensores):
        global CLASS_NAMES, CSAM_SCORE, PORN_SCORE, AI_CLASSIFICATION_SKIP_ATTR, AI_CLASSIFICATION_SKIP_NO
        
        """Processa um lote e atribui os scores de csam e porn, salvando ambos no cache."""
        predicoes_lote = self.fazer_predicao(tensores)
        csam_idx = CLASS_NAMES.index('csam')
        porn_idx = CLASS_NAMES.index('porn')
        cache = caseData.getCaseObject('csam_cache_unificado')

        for i, item in enumerate(items):
            predicoes_item = predicoes_lote[i]
            
            csam_score_float = predicoes_item[csam_idx]
            porn_score_float = predicoes_item[porn_idx]
            
            csam_score_formatado = int(csam_score_float*100)
            porn_score_formatado = int(porn_score_float*100)
            
            item.setExtraAttribute(CSAM_SCORE, csam_score_formatado)
            item.setExtraAttribute(PORN_SCORE, porn_score_formatado)
            item.setExtraAttribute(AI_CLASSIFICATION_SKIP_ATTR, AI_CLASSIFICATION_SKIP_NO)
            
            cache.put(item.getHash(), (csam_score_formatado, porn_score_formatado))

