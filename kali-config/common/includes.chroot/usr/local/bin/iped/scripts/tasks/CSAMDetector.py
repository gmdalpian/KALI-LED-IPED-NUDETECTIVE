"""
IPED task to detect Child Sexual Abuse Material (CSAM) using a TensorFlow or PyTorch based AI model.

The script must be enabled in IPED, and related PIP packages must be installed (tensorflow or torch, torchvision, timm, pillow).

On Linux, you need to install jep (pip install jep) and include jep.so in LD_LIBRARY_PATH.
see https://github.com/sepinf-inc/IPED/wiki/User-Manual#python-modules
"""

__author__ = "Guilherme Dalpian"
__email__ = "gmdalpian@gmail.com"
__version__ = "0.1"

import traceback
import io
import os
import time
import sys
from java.lang import System
from iped.engine.task import HashDBLookupTask

# --- Placeholders for Late Loading Tensorflow ---
tf = None
keras = None
# --- Placeholders for Late Loading PyTorch ---
torch = None
nn = None
timm = None
transforms = None
Image = None

# --- Global Configurations ---
PLUGIN_ENABLE_PROP = 'enableCSAMDetector'
CSAM_CONFIG_FILE = 'CSAMDetector.txt'
CSAM_SCORE = 'csam_score'
MODEL_SEMAPHORE = None

# Default parameter, changed to 480 when using large models
CSAM_IMG_SIZE = 224

# --- Global Control Variables ---
MOTOR_IA = None
MODELO_CARREGADO = None
DEVICE = None
CACHE = None

# Configurable parameters defaults
PLUGIN_ENABLED = False
CSAM_MODELFILE = 'tensorflow_b0_v1.keras'
CSAM_BATCH_SIZE = 64
CSAM_MINIMUM_IMAGE_SIZE = 0  # in bytes
CSAM_SKIP_DIMENSION = 0  # in pixels
CSAM_SKIP_HASHDB_FILES = 'false'  # skip files with hits on IPED HashDB database

CSAM_MODELFILE_PROPERTY = 'CSAMModelFile'
CSAM_BATCH_SIZE_PROPERTY = 'CSAMBatchSize'
CSAM_MINIMUM_IMAGE_SIZE_PROPERTY = 'CSAMMinimumImageSize'
CSAM_SKIP_DIMENSION_PROPERTY = 'CSAMSkipDimension'
CSAM_SKIP_HASHDB_FILES_PROPERTY = 'CSAMSkipHashDBFiles'

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
    global MODELO_CARREGADO, DEVICE, CACHE, CSAM_IMG_SIZE, CSAM_BATCH_SIZE
    
    MODELO_CARREGADO = caseData.getCaseObject('csam_model_unificado')
    if MODELO_CARREGADO is None:
        caminho_modelo = System.getProperty('iped.root') + '/models/' + CSAM_MODELFILE
        if not os.path.exists(caminho_modelo):
            logger.warn(f"FATAL ERROR: Model file not found: {caminho_modelo}")
            return None

        # --- Parameter Decision Logic ---
        nome_modelo_lower = CSAM_MODELFILE.lower()
        if "large" in nome_modelo_lower:
            CSAM_IMG_SIZE = 480
            logger.info("Detected 'Large' model. Using IMG_SIZE=480.")
        else: # Default for b0 or others
            CSAM_IMG_SIZE = 224
            logger.info("Detected 'B0' (or default) model. Using IMG_SIZE=224.")

        # --- Framework-Specific Loading ---
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
                
                modelo_timm = 'tf_efficientnetv2_l.in21k' if "large" in nome_modelo_lower else 'tf_efficientnetv2_b0'
                MODELO_CARREGADO = timm.create_model(modelo_timm, pretrained=False, num_classes=1)
                
                state_dict = torch.load(caminho_modelo, map_location=DEVICE)
                if list(state_dict.keys())[0].startswith('_orig_mod.'):
                    from collections import OrderedDict
                    new_state_dict = OrderedDict()
                    for k, v in state_dict.items():
                        new_state_dict[k[10:]] = v
                    state_dict = new_state_dict
                
                MODELO_CARREGADO.load_state_dict(state_dict)
                MODELO_CARREGADO.to(DEVICE)
                MODELO_CARREGADO.eval()
                logger.info(f"PyTorch model loaded successfully on device: {DEVICE}")
            except Exception as e:
                logger.warn(f"FATAL ERROR loading PyTorch model: {e}")
                return None
        
        caseData.putCaseObject('csam_model_unificado', MODELO_CARREGADO)
        
        if(not CACHE):
            from java.util.concurrent import ConcurrentHashMap
            CACHE = ConcurrentHashMap()
            caseData.putCaseObject('csam_cache_unificado', CACHE)

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

        if MOTOR_IA == 'tensorflow':
            img = tf.io.read_file(file_path)
            img = tf.io.decode_image(img, channels=3, expand_animations=False)
            img = tf.image.resize(img, [CSAM_IMG_SIZE, CSAM_IMG_SIZE])
            return img
        
        elif MOTOR_IA == 'pytorch':
            transform = transforms.Compose([
                transforms.Resize((CSAM_IMG_SIZE, CSAM_IMG_SIZE)),
                transforms.ToTensor(),
                transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225])
            ])
            image = Image.open(file_path).convert('RGB')
            return transform(image)

    except Exception as e:
        logger.warn(f"Error processing image {item.getPath()}, trying thumbnail... {e}")
        try:
            image_bytes = bytes(b % 256 for b in item.getThumb())
            if MOTOR_IA == 'tensorflow':
                img = tf.io.decode_image(image_bytes, channels=3, expand_animations=False)
                img = tf.image.resize(img, [CSAM_IMG_SIZE, CSAM_IMG_SIZE])
                return img
            elif MOTOR_IA == 'pytorch':
                # Reuses the same transform defined above
                transform = transforms.Compose([
                    transforms.Resize((CSAM_IMG_SIZE, CSAM_IMG_SIZE)),
                    transforms.ToTensor(),
                    transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225])
                ])
                image = Image.open(io.BytesIO(image_bytes)).convert('RGB')
                return transform(image)
        except Exception as thumb_e:
            logger.error(f"Failed to process thumbnail for {item.getPath()}: {thumb_e}")
            return None

def fazer_predicao(tensores):
    """Runs batch prediction using the correct AI engine."""
    try:
        MODEL_SEMAPHORE.acquire()
        if MOTOR_IA == 'tensorflow':
            lote = tf.stack(tensores)
            predicoes = MODELO_CARREGADO.predict(lote, verbose=0)
            return predicoes
        
        elif MOTOR_IA == 'pytorch':
            lote = torch.stack(tensores).to(DEVICE)
            with torch.no_grad():
                outputs = MODELO_CARREGADO(lote)
                predicoes = torch.sigmoid(outputs).cpu().numpy()
            return predicoes
    finally:
        MODEL_SEMAPHORE.release()

def processar_lote_de_imagens(items, tensores):
    """Unified function to process a batch and assign results."""
    predicoes = fazer_predicao(tensores)
    for i, item in enumerate(items):
        score = extrair_e_formatar_dois_digitos(predicoes[i][0])
        item.setExtraAttribute(CSAM_SCORE, score)
        item.setExtraAttribute(AI_CLASSIFICATION_SKIP_ATTR, AI_CLASSIFICATION_SKIP_NO)
        CACHE.put(item.getHash(), score)

def createSemaphore():
    global MODEL_SEMAPHORE
    MODEL_SEMAPHORE = caseData.getCaseObject('CSAM_SEMAPHORE')
    if(MODEL_SEMAPHORE is None):
        from java.util.concurrent import Semaphore
        MODEL_SEMAPHORE = Semaphore(1)
        caseData.putCaseObject('CSAM_SEMAPHORE', MODEL_SEMAPHORE)
    return MODEL_SEMAPHORE
    
def extrair_e_formatar_dois_digitos(score):
  """
  Extracts the two integer digits before the comma.
  If the result is less than 10, fills with a leading zero.
  """
  numero = score*100
  # Handles the case where the score is 100%, reducing to 99 to keep two digits
  if(numero==100):
      return "99"      
  # Isolates the part of the number (e.g.: 123.45 -> 23.45)
  numero_reduzido = numero % 100  
  # Removes the decimal part, without rounding (e.g.: 23.45 -> 23)
  parte_inteira = int(numero_reduzido)  
  # Formats to always have 2 digits, filling with 0 if necessary
  return f'{parte_inteira:02d}' 

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

    def isEnabled(self):
        return PLUGIN_ENABLED

    def processQueueEnd(self):
        return True
       
    def getConfigurables(self):
        from iped.engine.config import DefaultTaskPropertiesConfig
        return [DefaultTaskPropertiesConfig(PLUGIN_ENABLE_PROP, CSAM_CONFIG_FILE)]        

    def init(self, configuration):
        global PLUGIN_ENABLED, MOTOR_IA, CSAM_MODELFILE
        global tf, keras, torch, nn, timm, transforms, Image
        
        taskConfig = configuration.getTaskConfigurable(CSAM_CONFIG_FILE)
        PLUGIN_ENABLED = taskConfig.isEnabled()

        if not PLUGIN_ENABLED:
            return
        
        extraProps = taskConfig.getConfiguration()
        
        if(extraProps):
            CSAM_MODELFILE = extraProps.getProperty(CSAM_MODELFILE_PROPERTY) if extraProps.getProperty(CSAM_MODELFILE_PROPERTY) is not None else CSAM_MODELFILE
            CSAM_BATCH_SIZE = int(extraProps.getProperty(CSAM_BATCH_SIZE_PROPERTY)) if extraProps.getProperty(CSAM_BATCH_SIZE_PROPERTY) is not None else CSAM_BATCH_SIZE
            CSAM_MINIMUM_IMAGE_SIZE = int(extraProps.getProperty(CSAM_MINIMUM_IMAGE_SIZE_PROPERTY)) if extraProps.getProperty(CSAM_MINIMUM_IMAGE_SIZE_PROPERTY) is not None else CSAM_MINIMUM_IMAGE_SIZE_PROPERTY
            CSAM_SKIP_DIMENSION = int(extraProps.getProperty(CSAM_SKIP_DIMENSION_PROPERTY)) if extraProps.getProperty(CSAM_SKIP_DIMENSION_PROPERTY) is not None else CSAM_SKIP_DIMENSION_PROPERTY
            skipDBFiles = extraProps.getProperty(CSAM_SKIP_HASHDB_FILES_PROPERTY) if extraProps.getProperty(CSAM_SKIP_HASHDB_FILES_PROPERTY) is not None else CSAM_SKIP_HASHDB_FILES_PROPERTY
            CSAM_SKIP_HASHDB_FILES = True if skipDBFiles.lower() == 'true' else False
        
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

        # Change to load CSAM_MODELFILE from settings
        # CSAM_MODELFILE = configuration.getTaskProperty(PLUGIN_ENABLE_PROP, "modelFile", CSAM_MODELFILE)
               
        if CSAM_MODELFILE.lower().startswith('tensorflow'):
            MOTOR_IA = 'tensorflow'
            if tf is None:
                logger.info("TensorFlow engine detected. Loading libraries...")
                os.environ['TF_CPP_MIN_LOG_LEVEL'] = '3'
                import tensorflow as tf_module
                from tensorflow import keras as keras_module
                tf = tf_module
                keras = keras_module
                logger.info("TensorFlow libraries loaded.")
        
        elif CSAM_MODELFILE.lower().startswith('pytorch'):
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
        else:
            logger.warn(f"ERROR: Could not determine AI engine from model name: {CSAM_MODELFILE}")
            PLUGIN_ENABLED = False
            return

        if not carregar_e_configurar_modelo():
             PLUGIN_ENABLED = False
             return

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

        if item.getHash() is not None:
            cache = caseData.getCaseObject('csam_cache_unificado')
            score = cache.get(item.getHash())
            if score is not None:
                logger.debug(f"CSAMDetector: found previous score for item {item.getName()} {score}")
                item.setExtraAttribute(CSAM_SCORE, score)                
                item.setExtraAttribute(AI_CLASSIFICATION_SKIP_ATTR, AI_CLASSIFICATION_SKIP_DUPLICATE)
                return

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
            processar_lote_de_imagens(self.itemList, self.imageBytes)


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
        logger.debug("CSAMDetector: CSAM analysis finished.")
        return True