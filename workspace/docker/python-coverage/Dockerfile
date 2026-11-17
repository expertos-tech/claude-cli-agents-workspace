# Image of the coverage check in scripts/validate.sh: coverage.py and the per-module gate.
FROM python:3.14.10-alpine@sha256:eb2c62658b8d51bff0acc408504b76521d02030de56a8a3c1e830083e89b89d2

ENV COVERAGE_FILE=/tmp/.coverage \
    PYTHONDONTWRITEBYTECODE=1

COPY requirements.txt check_coverage.py run_coverage.py /opt/python-coverage/
# pip is not needed at run time and its vendored packages carry known vulnerabilities.
RUN pip install --no-cache-dir --disable-pip-version-check --root-user-action=ignore \
    --only-binary :all: --require-hashes -r /opt/python-coverage/requirements.txt \
    && pip uninstall --yes --disable-pip-version-check --root-user-action=ignore pip

USER 65534:65534
ENTRYPOINT ["python", "/opt/python-coverage/run_coverage.py"]
