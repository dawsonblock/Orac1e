import logging
import uuid
from typing import List, Optional
from PIL import Image

try:
    import pytesseract
except ImportError:
    pytesseract = None

from schema.element import VisionElement

logger = logging.getLogger(__name__)

class TextRegionDetector:
    """
    Detects text regions in an image using OCR (e.g., Tesseract).
    """
    
    def __init__(self):
        if pytesseract is None:
            logger.error("pytesseract is not installed. TextRegionDetector will run in stub mode.")
        logger.info("Initialized Text Region Detector")
        
    def detect(self, image: Image.Image, screen_w: float, screen_h: float) -> List[VisionElement]:
        """
        Detect text regions in the image.
        """
        elements: List[VisionElement] = []

        if pytesseract is None:
            return elements
        
        try:
            # We want bounding boxes per word or line
            data = pytesseract.image_to_data(image, output_type=pytesseract.Output.DICT)
            
            orig_w, orig_h = image.size
            # scale factors to screen coordinates
            scale_x = screen_w / orig_w if orig_w else 1.0
            scale_y = screen_h / orig_h if orig_h else 1.0

            n_boxes = len(data['level'])
            for i in range(n_boxes):
                text = data['text'][i].strip()
                conf = data['conf'][i]
                # In PyTesseract, conf is a string or int out of 100. Empty or invalid can be '-1'
                try:
                    conf_float = float(conf)
                except ValueError:
                    conf_float = -1.0
                
                # Only keep confident, non-empty text regions
                if conf_float > 30 and text:
                    x_img = data['left'][i]
                    y_img = data['top'][i]
                    w_img = data['width'][i]
                    h_img = data['height'][i]
                    
                    # scale to screen dimensions
                    x = float(x_img) * scale_x
                    y = float(y_img) * scale_y
                    w = float(w_img) * scale_x
                    h = float(h_img) * scale_y
                    
                    element = VisionElement(
                        id=f"ocr_text_{uuid.uuid4().hex[:8]}",
                        type="text",
                        text=text,
                        confidence=conf_float / 100.0,  # Normalize to 0-1
                        x=x, y=y, width=w, height=h,
                        source="ocr"
                    )
                    elements.append(element)
                    
        except Exception as e:
            logger.error(f"OCR detection failed: {e}")

        return elements

