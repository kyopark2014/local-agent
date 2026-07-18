import logging

from fastapi import APIRouter, File, HTTPException, Request, UploadFile

from application.api.routes_auth import require_user_id

logger = logging.getLogger("routes_rag")

router = APIRouter(prefix="/api/rag", tags=["rag"])


@router.post("/upload")
async def upload_to_rag(request: Request, file: UploadFile = File(...)):
    """Disabled: local-agent queries an existing Knowledge Base; it does not ingest via S3."""
    require_user_id(request)
    raise HTTPException(
        status_code=410,
        detail=(
            "RAG document upload is disabled in local-agent. "
            "Use the retrieve skill / knowledge base MCP against an existing KB."
        ),
    )
