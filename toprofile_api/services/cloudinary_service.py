import logging
import cloudinary.uploader as cu

logger = logging.getLogger(__name__)

class CloudinaryUploadError(Exception):
    pass

def upload_property_image(file, *, folder: str = "properties"):
    """
    Upload a single image to Cloudinary. Raises CloudinaryUploadError if anything looks off.
    """
    logger.debug("Cloudinary upload start: folder=%s name=%s size=%s",
                 folder, getattr(file, "name", None), getattr(file, "size", None))
    try:
        res = cu.upload(
            file,
            folder=folder,
            resource_type="image",
            unique_filename=True,
            overwrite=False,
        )
        logger.debug("Cloudinary raw response: %s", res)

        url = res.get("secure_url") or res.get("url")
        public_id = res.get("public_id")
        if not url or not public_id:
            raise CloudinaryUploadError(f"Missing url/public_id in response: {res}")

        return {
            "url": url,
            "public_id": public_id,
            "width": res.get("width"),
            "height": res.get("height"),
            "format": res.get("format"),
        }
    except Exception as e:
        logger.exception("Cloudinary upload failed")
        raise CloudinaryUploadError(str(e)) from e


def delete_image(public_id: str):
    try:
        logger.debug("Cloudinary delete start: public_id=%s", public_id)
        return cu.destroy(public_id, invalidate=True)
    except Exception:
        logger.exception("Cloudinary delete failed for %s", public_id)
        # don't re-raise during cleanup
        return None
