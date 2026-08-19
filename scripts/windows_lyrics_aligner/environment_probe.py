import json
import platform

import torch


def main() -> None:
    cuda_available = torch.cuda.is_available()
    payload = {
        "python": platform.python_version(),
        "torch": torch.__version__,
        "cuda_available": cuda_available,
        "cuda_runtime": torch.version.cuda,
        "device": torch.cuda.get_device_name(0) if cuda_available else None,
        "device_memory_bytes": (
            torch.cuda.get_device_properties(0).total_memory if cuda_available else None
        ),
        "bf16_supported": torch.cuda.is_bf16_supported() if cuda_available else False,
    }
    print(json.dumps(payload, ensure_ascii=False))


if __name__ == "__main__":
    main()
