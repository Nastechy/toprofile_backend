from django.urls import path as url,re_path
from .views import (
                    AdminSignUpAPiView,
                    LoginApiView,
                    EmailOTpVerificationApiView,
                    ResetPasswordApiView,
                    LogoutView,
                    RefreshTokenView,
                    UserProfile,
                    UserEmailVerification,
                    UserListApiView,
                    SingleUserApiView
                    )
urlpatterns = [
url('auth/sign-up/',AdminSignUpAPiView.as_view()),
url('auth/users/',UserListApiView.as_view()),
url('auth/users/<uuid:id>/',SingleUserApiView.as_view()),
url('users/',UserListApiView.as_view()),
url('users/<uuid:id>/',SingleUserApiView.as_view()),
url('auth/login/',LoginApiView.as_view()),
url('auth/email/otp/verification/',EmailOTpVerificationApiView.as_view()),
url('auth/email/verification/',UserEmailVerification.as_view()),
url('reset-password/',ResetPasswordApiView.as_view()),
# url('token/refresh/',RefreshTokenView.as_view()),
url('logout/',LogoutView.as_view()),
url("user/profile/",UserProfile.as_view())
]
