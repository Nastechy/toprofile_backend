from datetime import datetime,timezone
import calendar
from .models import MostViewPage
from .constant import MONTH

def get_analytics(year) -> list:
    """Returns the monthly analytics of the invoices passed as parameter"""
    result = []
    today = datetime.utcnow().replace(tzinfo=timezone.utc)
    result = [
        {
        
            "month": calendar.month_abbr[month_no],
            "count":MostViewPage.objects.filter(
                month=calendar.month_abbr[month_no],
                year=str(year)
            ).first().count
            if MostViewPage.objects.filter(
                month=calendar.month_abbr[month_no],
                year=str(year)
            ).first()
            else int(0),
        }
        for month_no in range(1, 13)
    ]

    return result