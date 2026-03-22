import logging
import uuid
import os
from typing import List, Optional
from PIL import Image

try:
    from ultralytics import YOLO
except ImportError:
    YOLO = None

from schema.element import VisionElement

logger = logging.getLogger(__name__)

class UIDetector:
    """
    Detects interactive UI elements like buttons, inputs, icons, etc.
    This is a stub for a YOLOv11 or similar object detection model.
    """
    
    def __init__(self, model_path: Optional[str] = None):
        self.model_path = model_path or "yolov8n.pt"
        self.model = None
        self._load_model()
        
    def _load_model(self):
        if YOLO is None:
            logger.error("ultralytics is not installed. UIDetector will run in stub mode.")
            return

        try:
            # Check if model exists, if not, Ultralytics downloads it automatically.
            if not os.path.exists(self.model_path):
                logger.warning(f"UIDetector: Model {self.model_path} not found. Operating using defaults.")
            self.model = YOLO(self.model_path)
            logger.info(f"Initialized UI Detector with model path: {self.model_path}")
        except Exception as e:
            logger.error(f"Failed to load YOLO model: {e}")
        
    def detect(self, image: Image.Image, screen_w: float, screen_h: float) -> List[VisionElement]:
        """
        Detect UI elements in the image.
        Returns a list of VisionElements with their bounding boxes and confidence.
        """
        elements: List[VisionElement] = []
        if not self.model:
            return elements

        # Run inference
        results = self.model(image)
        
        orig_w, orig_h = image.size
        # scale factors to screen coordinates
        scale_x = screen_w / orig_w if orig_w else 1.0
        scale_y = screen_h / orig_h if orig_h else 1.0

        for r in results:
            boxes = r.boxes
            for box in boxes:
                # bounding box in x1, y1, x2, y2 format
                x1, y1, x2, y2 = box.xyxy[0].tolist()
                conf = float(box.conf[0])
                cls_idx = int(box.cls[0])
                
                # Use model names dictionary or fallback
                element_type = r.names[cls_idx] if hasattr(r, 'names') and r.names else f"class_{cls_idx}"
                
                # scale to screen dimensions
                x = x1 * scale_x
                y = y1 * scale_y
                w = (x2 - x1) * scale_x
                h = (y2 - y1) * scale_y
                
                element = VisionElement(
                    id=f"yolo_ui_{uuid.uuid4().hex[:8]}",
                    type=element_type,
                    confidence=conf,
                    x=x, y=y, width=w, height=h,
                    source="yolo"
                )
                elements.append(element)

        return elements

