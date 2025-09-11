import functools

def swagger_safe(model):
    def decorator(func):
        @functools.wraps(func)
        def wrapper(self, *args, **kwargs):
            if getattr(self, 'swagger_fake_view', False):
                return model.objects.none()
            return func(self, *args, **kwargs)
        return wrapper
    return decorator