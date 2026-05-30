from functools import wraps


def safe_stage(stage, default=None):
    def decorator(fn):

        @wraps(fn)
        def wrapper(*args, **kwargs):
            errors = kwargs.get("errors")

            try:
                return fn(*args, **kwargs)

            except Exception as e:
                if errors is not None:
                    errors.append({
                        "stage": stage,
                        "error": str(e)
                    })

                return default

        return wrapper

    return decorator