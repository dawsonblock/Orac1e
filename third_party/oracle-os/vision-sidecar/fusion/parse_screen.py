import logging
from typing import List, Dict, Any, Optional
from PIL import Image

from detectors.ui_detector import UIDetector
from detectors.text_region_detector import TextRegionDetector
from fusion.rank_candidates import CandidateRanker
from schema.element import VisionElement

logger = logging.getLogger(__name__)

class ScreenParser:
    """
    Orchestrates the detection of UI components and text regions to form a 
    structured representation of the screen via purely visual means.
    """
    
    def __init__(self, model_path: Optional[str] = None):
        self.ui_detector = UIDetector(model_path=model_path)
        self.text_detector = TextRegionDetector()
        self.ranker = CandidateRanker()
        
    def parse(self, image: Image.Image, screen_w: float, screen_h: float) -> Dict[str, Any]:
        """
        Parse the screen image into a structured map.
        Returns a dict containing ranked interactive elements and context.
        """
        ui_elements = self.ui_detector.detect(image, screen_w, screen_h)
        text_elements = self.text_detector.detect(image, screen_w, screen_h)
        
        all_elements = ui_elements + text_elements
        ranked_candidates = self.ranker.rank(all_elements)
        
        return {
            "status": "success",
            "elements": [e.to_dict() for e in ranked_candidates],
            "count": len(ranked_candidates),
            "context": "Screen parsed successfully via vision detectors."
        }
