"""Compatibility entry point for the inference benchmark CLI."""

from .run_inference import main


if __name__ == "__main__":
    raise SystemExit(main())
