from django.utils.crypto import get_random_string
import string
from .models import EmailVerification
from django.template.loader import render_to_string
from django.conf import settings
from django.core.mail import send_mail
from rest_framework_simplejwt.tokens import RefreshToken
from django.core.mail import EmailMultiAlternatives
from django.utils.html import strip_tags

def send_emails(email,instance=None):
        try:
            otp=get_random_string(5,allowed_chars=string.digits)
            subject = 'Confirm Your Email Address'
            message = render_to_string('accounts/email_confirmation.html', {
            "otp":otp,
            "username":instance.username if instance else "user"
        })
            from_email = settings.EMAIL_HOST_USER
            to_email = email
            text_content = strip_tags(message)
            # send_mail(subject, message, from_email, [to_email], fail_silently=False)
            msg = EmailMultiAlternatives(subject, text_content, from_email, [to_email])
            msg.attach_alternative(message, "text/html")
            msg.send()

            #save the email and the otp to email verification table
            EmailVerification.objects.filter(email=email).delete()
            EmailVerification.objects.create(email=email,otp=otp)
        except Exception as e:
             raise RuntimeError("Error in sending email")
             return None


def jwt_token(user):
    data={}
    refresh=RefreshToken.for_user(user)   
    data["refresh"] = str(refresh)
    data["access"] = str(refresh.access_token)
    return data