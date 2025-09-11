from typing import Iterable, Optional
from django.db import models
from django.contrib.auth.models import AbstractBaseUser,PermissionsMixin,BaseUserManager
from django.contrib.auth.hashers import make_password
from django.contrib import auth
import uuid
import re
from django.utils.translation import gettext_lazy as _
from django.utils import timezone
from django.apps import apps
from django.conf import settings

SPECIAL_CHARS_REGEX = "[^a-zA-Z0-9 \n\.]"

class CustomUserManager(BaseUserManager):
    use_in_migrations = True
    def _create_user(self,email, password, **extra_fields):
        if not email:
            raise ValueError("The given email must be set")
        email = self.normalize_email(email)
        GlobalUserModel = apps.get_model(
            self.model._meta.app_label, self.model._meta.object_name
        )
        email = GlobalUserModel.normalize_username(email)
        user = self.model(email=email, **extra_fields)
        user.password = make_password(password)
        user.save(using=self._db)
        return user

    def create_user(self, email=None, password=None, **extra_fields):
        extra_fields.setdefault("is_staff", False)
        extra_fields.setdefault("is_superuser", False)
        return self._create_user(email, password, **extra_fields)

    def create_superuser(self, email=None, password=None, **extra_fields):
        extra_fields.setdefault("is_staff", True)
        extra_fields.setdefault("is_superuser", True)

        if extra_fields.get("is_staff") is not True:
            raise ValueError("Superuser must have is_staff=True.")
        if extra_fields.get("is_superuser") is not True:
            raise ValueError("Superuser must have is_superuser=True.")

        return self._create_user(email, password, **extra_fields)
    
class CustomUser(AbstractBaseUser,PermissionsMixin):
    id=models.UUIDField(primary_key=True,editable=False,db_index=True,default=uuid.uuid4)
    full_name=None
    username=models.CharField(_("Username"),max_length=400,null=True,blank=True)
    phone_number=models.CharField(_("Phone Number"),max_length=400,null=True,blank=True)
    email=models.EmailField(_("Email Address"),unique=True,db_index=True)
    address=models.CharField(max_length=1000,null=True)
    is_staff = models.BooleanField(_("staff status"), default=False )
    is_active = models.BooleanField( _("active"),default=True,)
    is_verified = models.BooleanField( _("Verified"),default=False)
    date_joined = models.DateTimeField(_("date joined"), default=timezone.now)
    terms_condition=models.BooleanField(default=False)

    
   
    EMAIL_FIELD = ""
    USERNAME_FIELD = "email"
    REQUIRED_FIELDS = ["username"]

    objects=CustomUserManager()

    def __str__(self) -> str:
        return self.email
    
class EmailVerificatiomManage(models.Manager):
    def get_queryset(self) -> models.QuerySet:
        return super().get_queryset()\
            .filter(date_generated__gte=timezone.now() - timezone.timedelta(minutes=5))

class EmailVerification(models.Model):
    id=models.UUIDField(primary_key=True,editable=False,db_index=True,default=uuid.uuid4)
    email=models.EmailField(_("Email"),unique=True,db_index=True)
    otp=models.CharField(max_length=5,unique=False,blank=True,null=True)
    date_generated=models.DateTimeField(auto_now=True)

    # objects=EmailVerificatiomManage()


    def __str__(self) -> str:
        return self.email
    