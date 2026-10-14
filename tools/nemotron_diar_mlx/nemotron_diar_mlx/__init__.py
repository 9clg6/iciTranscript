"""Portage MLX (Apple Silicon) de NVIDIA Nemotron 3 Diarization."""

from .config import ModelConfig
from .model import Model

__all__ = ["Model", "ModelConfig"]
