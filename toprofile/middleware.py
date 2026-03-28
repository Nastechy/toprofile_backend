from toprofile_api.models import Device,MostViewPage
from django.utils.deprecation import MiddlewareMixin
from datetime import datetime,timezone
from toprofile_api.constant import MONTH
import calendar
class DeviceTrackerMiddleware(MiddlewareMixin):

    def process_request(self, request):
        # Tracking should never block the actual API action.
        try:
            user_agent = request.META.get('HTTP_USER_AGENT', '').lower()
            if request.path != "/":
                if "iphone" in user_agent:
                    Device.objects.create(name="Mobile")
                if "macintosh" in user_agent:
                    Device.objects.create(name="Web")
                if "android" in user_agent:
                    Device.objects.create(name="Mobile")
                if "windows" in user_agent:
                    Device.objects.create(name="Web")
        except Exception:
            # Ignore tracker failures to avoid returning 500 for business endpoints.
            pass
        return None

class MostViewPageMiddleware(MiddlewareMixin):

    def process_request(self, request):
        # Tracking should never block the actual API action.
        try:
            # home,property,blog
            if "home" in request.path:
                date_obj = datetime.utcnow().replace(tzinfo=timezone.utc)
                month = date_obj.month
                year = date_obj.year
                obj, created = MostViewPage.objects.get_or_create(
                    month=calendar.month_abbr[month],
                    year=str(year),
                    defaults={
                        "month": calendar.month_abbr[month],
                        "year": str(year)
                    }
                )
                if not created:
                    obj.count += 1
                    obj.save()
        except Exception:
            # Ignore tracker failures to avoid returning 500 for business endpoints.
            pass
        return None
