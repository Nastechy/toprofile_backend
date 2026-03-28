from rest_framework import serializers
from django.contrib.auth import get_user_model
from rest_framework_simplejwt.serializers import TokenObtainSerializer
from rest_framework_simplejwt.tokens import RefreshToken
# from .services import check_isactive,check_verification
from django.utils.translation import gettext_lazy as _
from rest_framework_simplejwt.settings import api_settings
from django.contrib.auth.models import update_last_login
from django.contrib.auth import get_user_model
from .models import EmailVerification
from django.db.models import Q
from rest_framework.views import APIView
User=get_user_model()

class AccountCreationSerializer(serializers.ModelSerializer):
    # Backward compatibility for older clients still posting `phonenumber`.
    phonenumber = serializers.CharField(
        required=False, allow_blank=True, allow_null=True, write_only=True
    )

    class Meta:
        model=get_user_model()
        fields=[
            "username",
            "phone_number",
            "phonenumber",
            "email",
            "password",
            "address",
            "terms_condition"

        ]
        extra_kwargs={
            "password":{
                "write_only":True
            }

        }

    def validate(self, attrs):
        legacy_phone_number = attrs.pop("phonenumber", None)
        if legacy_phone_number and not attrs.get("phone_number"):
            attrs["phone_number"] = legacy_phone_number

        email = attrs.get("email")
        if email and User.objects.filter(email__iexact=email).exists():
            raise serializers.ValidationError({"email": "This field already exists"})

        return attrs
        
    def create(self, validated_data):
        password = validated_data.pop("password")
        user = User.objects.create_user(password=password, **validated_data)
        return user
    
class TokenObtainPairSerializer(TokenObtainSerializer):
    default_error_messages = {
        "no_active_account": _("login provided credentials does not exist")
    }
    token_class = RefreshToken
    
    def validate_email(self,data):
        if User.objects.filter(Q(email__iexact=data)|Q(username__iexact=data)).exists():
            return data
        raise serializers.ValidationError("email does not exist")
    
    def validate(self, attrs):
            data = super().validate(attrs)
        # # check if the user is still is active or not
        #     check_isactive(self.user)
        #     # check if the user is verified before he can successfully login in
        #     check_verification(self.user) 
            refresh = self.get_token(self.user)
            data["refresh"] = str(refresh)
            data["access"] = str(refresh.access_token)

            if api_settings.UPDATE_LAST_LOGIN:
                update_last_login(None,self.user)

            return data
    
class EmailVerificationSerailaizer(serializers.Serializer):
    email=serializers.EmailField(required=True)
    otp=serializers.CharField(max_length=5,required=True)

            
    # def validate(self, attrs):
    #     email=attrs.get('email',None)
    #     if email is None:
    #         raise serializers.ValidationError({"detail":"please enter a valid Email"})
    #     return attrs
    
class UserEmailVerificationSerailaizer(serializers.Serializer):
    email=serializers.EmailField(required=True,write_only=True)
         
class ForgetPasswordInputSerializer(serializers.Serializer):
    email=serializers.CharField(required=True,max_length=20)
    password=serializers.CharField(required=True, write_only=True)
    confirm_password=serializers.CharField(required=True,write_only=True)
    otp=serializers.CharField(required=True,write_only=True,max_length=6)

    def validate(self, attrs):
        if attrs['password']==attrs['confirm_password']:
            return attrs
        raise serializers.ValidationError("password doesn't match")

    def create(self, validated_data):
        try:   
            new_password=validated_data.get('password')
            user=User.objects.get(email__iexact=validated_data['email'])
            user.set_password(new_password)
            user.confirm_password=user.password
            user.save()
        except Exception as e:
            raise serializers.ValidationError(e)
        return user
    
class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model=get_user_model()
        fields=[
            "username",
            "phone_number",
            "email"
        ]
        extra_kwargs={
            "email":{
                "read_only":True
            }
        }
