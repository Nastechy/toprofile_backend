from .models import *
from rest_framework import serializers
from drf_extra_fields.fields import HybridImageField

class CustomHybridImageField(HybridImageField):
    class Meta:
        swagger_schema_fields = {
            'type': 'String',
            'title': 'Image Content',
            'description': 'Content of the base64 encoded images',
            'read_only': False  # <-- FIX
        }
class PropertyCategorySerializer(serializers.ModelSerializer):
    class Meta:
        model=PropertyCategory
        fields="__all__"

class BlogSerializer(serializers.ModelSerializer):
    comment=serializers.SerializerMethodField()
    view=serializers.SerializerMethodField()
    image=CustomHybridImageField(required=False)
    class Meta:
        model=Blog
        fields="__all__"
        extra_kwargs={
            "slug":{
                "read_only":True
            }
        }

    def get_comment(self,obj):
        return int(20)
    
    def get_view(self,obj):
        return sum([blog.count for blog in obj.blogView.all()])
    
class ImageAssetSerializer(serializers.ModelSerializer):
    image=CustomHybridImageField(required=False)
    class Meta:
        model=ImageAsset
        fields=[
            "id",
            "image"
        ]
        extra_kwargs={
            "id":{
                "read_only":True
            }
           
        }

class PropertyInputSerializer(serializers.ModelSerializer):
    propertyImages=ImageAssetSerializer(many=True,required=False)
    class Meta:
        model=PropertyListing
        exclude=[
            "slug"
        ]
        
        
class PropertyOutputSerializer(serializers.ModelSerializer):
    propertyImages=ImageAssetSerializer(many=True)
    class Meta:
        model=PropertyListing
        fields="__all__"
        depth=1
        

class HeroSectionSerializer(serializers.ModelSerializer):
    image=CustomHybridImageField(required=False)
    class Meta:
        model=HeroSection
        fields="__all__"

class FeatureSectionSerializer(serializers.ModelSerializer):
    class Meta:
        model=FeatureSection
        fields="__all__"

class AboutUseSerializer(serializers.ModelSerializer):
    image=CustomHybridImageField(required=False)
    class Meta:
        model=AboutUs
        fields="__all__"

class OurServiceSerializer(serializers.ModelSerializer):
    image=CustomHybridImageField(required=False)
    class Meta:
        model=OurServices
        fields="__all__"

class  OurTeamSerializer(serializers.ModelSerializer):
    image=CustomHybridImageField(required=False)
    class Meta:
        model=OurTeam
        fields="__all__"

class TestimonySerializer(serializers.ModelSerializer):
    image=CustomHybridImageField(required=False)
    class Meta:
        model=Testimony
        fields="__all__"

class FillFormserializer(serializers.ModelSerializer):
    class Meta:
        model=FillContactForm
        fields="__all__"

class  AgentSerializer(serializers.ModelSerializer):
    class Meta:
        model=Agent
        fields="__all__"
    
class  AgentReadSerializer(serializers.ModelSerializer):
    agent=serializers.SerializerMethodField(read_only=True)
    class Meta:
        model=Agent
        fields="__all__"
    
    def get_agent(self,obj):
        return AgentMemberSerializer(obj.agent.all(),many=True).data

class  AgentMemberSerializer(serializers.ModelSerializer):
    image=CustomHybridImageField(required=False)
    class Meta:
        model=AgentMember
        fields="__all__"

class ReUsableSerializer(serializers.Serializer):
    id=serializers.IntegerField(read_only=True)
    content=serializers.CharField(required=True)

class AdminAppearanceSerializer(serializers.ModelSerializer):
    class Meta:
        model=AdminAppearance
        fields="__all__"

class DeviceSerializer(serializers.Serializer):
    name=serializers.CharField()
    name_count=serializers.IntegerField()