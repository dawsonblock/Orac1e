import logging
from typing import List, Optional
from schema.element import VisionElement

logger = logging.getLogger(__name__)

class CandidateRanker:
    """
    Fuses and ranks candidates from multiple vision sources (YOLO, OCR, VLM).
    """
    
    def rank(self, elements: List[VisionElement], query: Optional[str] = None) -> List[VisionElement]:
        """
        Rank elements based on confidence, type relevance, and distance.
        If a query is provided, semantic matching (via embeddings or exact text match)
        can be used to boost relevance.
        """
        # Remove empty or extremely low confidence elements
        valid_elements = [e for e in elements if e.confidence > 0.1]
        
        # Simple sorting: Highest confidence first
        # In a real system: Merge overlapping boxes (NMS), give hierarchy
        ranked = sorted(valid_elements, key=lambda e: e.confidence, reverse=True)
        
        # Deduplicate overlapping bounding boxes across OCR and YOLO 
        # (e.g. YOLO says "button" with box A, OCR says text says "Submit" overlapping box A)
        final_elements = self._merge_overlaps(ranked)
        
        return final_elements
        
    def _merge_overlaps(self, elements: List[VisionElement], iou_threshold: float = 0.5) -> List[VisionElement]:
        """
        Merge overlapping elements from different modalities.
        Matches OCR text into YOLO container elements if they overlap.
        """
        merged: List[VisionElement] = []
        # basic implementation of non-maximum suppression or merging 
        # would go here. For now, just return as-is.
        return elements
