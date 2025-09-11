from toprofile_api.models import Device,MostViewPage
from django.utils.deprecation import MiddlewareMixin
from datetime import datetime,timezone
from toprofile_api.constant import MONTH
import calendar
class DeviceTrackerMiddleware(MiddlewareMixin):
        
    def process_request(self, request):
        # Code to be executed for each request before
        # the view (and later middleware) are called.

        response = self.get_response(request)
        user_agent=request.META.get('HTTP_USER_AGENT', '').lower()
        if request.path != "/":
            if "iphone" in user_agent:
                Device.objects.create(
                    name="Mobile"
                )
            if "macintosh" in user_agent:
                Device.objects.create(
                    name="Web"
                )
            if "android" in user_agent:
                Device.objects.create(
                    name="Mobile"
                )
            if "windows" in user_agent:
                Device.objects.create(
                    name="Web"
                )
        return response
    
class MostViewPageMiddleware(MiddlewareMixin):
        
    def process_request(self, request):
        # Code to be executed for each request before
        # the view (and later middleware) are called.

        response = self.get_response(request)
        #home,property,blog
        if "home" in request.path:
            date_obj = datetime.utcnow().replace(tzinfo=timezone.utc)
            month=date_obj.month
            year=date_obj.year
            obj,created=MostViewPage.objects.get_or_create(
                month=calendar.month_abbr[month],
                year=str(year),
                defaults={
                    "month":calendar.month_abbr[month],
                    "year":str(year)
                }
            )
            if not created:
                obj.count +=1
                obj.save()
        return response