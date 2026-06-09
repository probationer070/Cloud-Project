FROM public.ecr.aws/lambda/python:3.12

# uv: Python package installer written in Rust, 10-100x faster than pip
# Pulled from the official uv image — no local install needed
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

COPY requirements.txt .
RUN uv pip install -r requirements.txt --no-cache --target "${LAMBDA_TASK_ROOT}"

COPY index.py "${LAMBDA_TASK_ROOT}/"

CMD ["index.lambda_handler"]
