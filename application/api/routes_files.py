import logging
import os
import uuid

from fastapi import APIRouter, File, HTTPException, Request, UploadFile

from application.api.routes_auth import require_user_id
from application import utils

logger = logging.getLogger("routes_files")

router = APIRouter(prefix="/api/files", tags=["files"])

IMAGE_ALLOWED_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp", ".gif"}


def _validate_image_filename(filename: str) -> str:
    name = os.path.basename(filename or "").strip()
    if not name:
        raise HTTPException(status_code=400, detail="File name is required")
    ext = os.path.splitext(name)[1].lower()
    if ext not in IMAGE_ALLOWED_EXTENSIONS:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported image type: {ext or '(none)'}",
        )
    stem = os.path.splitext(name)[0] or "pasted"
    unique = uuid.uuid4().hex[:10]
    return f"{stem}_{unique}{ext}"


@router.post("/upload")
async def upload_file(request: Request, file: UploadFile = File(...)):
    """Upload an image to application/uploads/ for chat attachment (no S3)."""
    require_user_id(request)

    file_name = _validate_image_filename(file.filename or "pasted.png")
    file_bytes = await file.read()
    if not file_bytes:
        raise HTTPException(status_code=400, detail="Empty file")

    upload_result = utils.save_upload_locally(file_bytes, file_name)
    if not upload_result:
        raise HTTPException(status_code=500, detail="Failed to save uploaded file")

    logger.info(
        "File upload complete: file=%s path=%s",
        file_name,
        upload_result.get("path"),
    )

    return {
        "ok": True,
        "file_name": upload_result["file_name"],
        "path": upload_result["path"],
        "url": upload_result["url"],
        "content_type": upload_result.get("content_type"),
    }
