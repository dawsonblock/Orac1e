from dataclasses import dataclass, field
from typing import Optional, List, Dict, Any

@dataclass
class VisionElement:
    """
    A UI element detected purely from pixels (YOLO + OCR).
    """
    id: str  # Unique identifier for this detection
    type: str  # e.g., "button", "text", "icon", "image", "input"
    confidence: float # Confidence score from the detector (0.0 to 1.0)
    
    # Bounding box in logical coordinates (x, y, width, height)
    x: float
    y: float
    width: float
    height: float
    
    # Text content (if any recognized via OCR or structure)
    text: Optional[str] = None
    
    # Source provenance
    source: str = "vision" # "yolo", "ocr", "vlm", etc.
    
    # Optional metadata or features from the model
    attributes: Dict[str, Any] = field(default_factory=dict)
    
    @property
    def center_x(self) -> float:
        return self.x + (self.width / 2)
        
    @property
    def center_y(self) -> float:
        return self.y + (self.height / 2)
    
    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "type": self.type,
            "confidence": self.confidence,
            "box": [self.x, self.y, self.width, self.height],
            "text": self.text,
            "source": self.source,
            "attributes": self.attributes
        }
