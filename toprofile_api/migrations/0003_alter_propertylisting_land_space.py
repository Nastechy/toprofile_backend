from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("toprofile_api", "0002_mission_vision"),
    ]

    operations = [
        migrations.AlterField(
            model_name="propertylisting",
            name="land_space",
            field=models.CharField(default="", max_length=255),
        ),
    ]
