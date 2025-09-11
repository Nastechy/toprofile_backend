from django.db import models
import uuid
import re
from .constant import STATUS
from datetime import datetime
from django.utils.text import slugify

SPECIAL_CHARS_REGEX = "[^a-zA-Z0-9 \n\.]"

class Blog(models.Model):
    def upload_to(instance, filename):
        url = re.sub(
            SPECIAL_CHARS_REGEX,
            "_",
            "images/profile/{filename}".format(filename=filename),
        )
        return url
    title=models.TextField(null=True)
    slug=models.SlugField(unique=True,blank=True,max_length=500)
    body=models.TextField(null=False,blank=False)
    author_name=models.CharField(max_length=300,null=True)
    image=models.ImageField(upload_to=upload_to,null=True)
    reading_time=models.CharField(max_length=300,null=True)
    created_at=models.DateTimeField(auto_now_add=True)

    def save(self, *args, **kwargs):
        if not self.slug:
            timestamp_str = datetime.now().strftime('%Y%m%d%H%M%S%f')[:-3]
            self.slug = slugify(f'{self.title}-{timestamp_str}')
        super(Blog, self).save(*args, **kwargs)
        
class BlogViews(models.Model):
    blog=models.ForeignKey(Blog,on_delete=models.CASCADE,related_name="blogView")
    count=models.BigIntegerField(default=1)
    created_at=models.DateTimeField(auto_now_add=True)

class PropertyCategory(models.Model):
    name=models.CharField(max_length=225,null=False)
    created_at=models.DateTimeField(auto_now_add=True)


class PropertyListing(models.Model):
    body=models.TextField()
    slug=models.SlugField(unique=True,blank=True,max_length=500)
    title=models.TextField()
    address=models.CharField(max_length=500,null=True)
    land_space=models.IntegerField(default=0)
    category=models.ForeignKey(PropertyCategory,on_delete=models.CASCADE,related_name="listings",null=True)
    amount=models.DecimalField(max_digits=10,decimal_places=0)
    created_at=models.DateTimeField(auto_now_add=True)

    def save(self, *args, **kwargs):
        if not self.slug:
            timestamp_str = datetime.now().strftime('%Y%m%d%H%M%S%f')[:-3]
            self.slug = slugify(f'{self.title}-{timestamp_str}')
        super(PropertyListing, self).save(*args, **kwargs)

class ImageAsset(models.Model):
    def upload_to(instance, filename):
        url = re.sub(
            SPECIAL_CHARS_REGEX,
            "_",
            "images/profile/{filename}".format(filename=filename),
        )
        return url
    image=models.ImageField(upload_to=upload_to)
    property=models.ForeignKey(PropertyListing,on_delete=models.CASCADE,null=True,blank=True,related_name="propertyImages")

class HeroSection(models.Model):
    def upload_to(instance, filename):
        url = re.sub(
            SPECIAL_CHARS_REGEX,
            "_",
            "images/profile/{filename}".format(filename=filename),
        )
        return url
    heading=models.TextField()
    sub_heading=models.TextField()
    image=models.ImageField(upload_to=upload_to,null=True)

class FeatureSection(models.Model):
    heading=models.TextField()
    sub_heading=models.TextField()

#About Us
class AboutUs(models.Model):
    def upload_to(instance, filename):
        url = re.sub(
            SPECIAL_CHARS_REGEX,
            "_",
            "images/about/{filename}".format(filename=filename),
        )
        return url
    image=models.ImageField(upload_to=upload_to,null=True)
    about=models.TextField()

class OurServices(models.Model):
    def upload_to(instance, filename):
        url = re.sub(
            SPECIAL_CHARS_REGEX,
            "_",
            "images/service/{filename}".format(filename=filename),
        )
        return url
    image=models.ImageField(upload_to=upload_to,max_length=500,null=True)
    title=models.CharField(max_length=500)
    content=models.TextField()

class OurTeam(models.Model):
    def upload_to(instance, filename):
        url = re.sub(
            SPECIAL_CHARS_REGEX,
            "_",
            "images/profile/{filename}".format(filename=filename),
        )
        return url
    image=models.ImageField(upload_to=upload_to,null=True)
    first_name=models.CharField(null=True,max_length=500)
    last_name=models.TextField(null=True,max_length=500)
    postion=models.TextField(null=True,max_length=500)
    facebook_link=models.URLField()
    instagram_link=models.URLField()
    email_link=models.URLField()
    twitter_link=models.URLField()


class FillContactForm(models.Model):
    full_name=models.TextField()
    email=models.EmailField()
    message=models.TextField()

#done
class AgentMember(models.Model):
    def upload_to(instance, filename):
        url = re.sub(
            SPECIAL_CHARS_REGEX,
            "_",
            "images/profile/{filename}".format(filename=filename),
        )
        return url
    name=models.TextField(null=False)
    image=models.ImageField(upload_to=upload_to,null=True)
    facebook_link=models.URLField(null=True)
    instagram_link=models.URLField(null=True)
    email_link=models.URLField(null=True)
    twitter_link=models.URLField(null=True)

class Agent(models.Model):
    heading=models.TextField(null=True)
    sub_heading=models.CharField(max_length=500,null=False)
    agent=models.ManyToManyField(AgentMember,related_name="agents")


class Testimony(models.Model):
    def upload_to(instance, filename):
        url = re.sub(
            SPECIAL_CHARS_REGEX,
            "_",
            "images/profile/{filename}".format(filename=filename),
        )
        return url
    name=models.TextField()
    comment=models.TextField()
    image=models.ImageField(upload_to=upload_to,null=True)
    created_at=models.DateTimeField(auto_now_add=True)

#PrivatePolicy
class PrivatePolicy(models.Model):
    content=models.TextField()
#Terms and Services
class TermsOfService(models.Model):
    content=models.TextField()


class AdminAppearance(models.Model):
    def upload_to(instance, filename):
        url = re.sub(
            SPECIAL_CHARS_REGEX,
            "_",
            "images/admin/{filename}".format(filename=filename),
        )
        return url
    logo=models.ImageField(upload_to=upload_to,null=True)
    icon=models.ImageField(upload_to=upload_to,null=True)
    background=models.ImageField(upload_to=upload_to,null=True)


class Device(models.Model):
    name=models.CharField(max_length=30,null=False)

class MostViewPage(models.Model):
    count=models.BigIntegerField(default=1)
    month=models.CharField(max_length=20,null=True)
    year=models.CharField(null=True,max_length=7)
    created_at=models.DateTimeField(auto_now_add=True,null=True)