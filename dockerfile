# Note: Some comments may seem over-explained or self explanatory, however, doing this to for myself look back at it and remember the concepts

FROM python:3.12-slim 
# Calling a mini virtual PC with stripped down python in it

WORKDIR /app

COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
# The --no-cache-dir flag is for not saving unnecessary installation files in docker container. 

COPY app/ .

EXPOSE 5000

CMD ["python", "app.py"]

# Important concept: The requirements has been copied and executed first separately.
# If everything was copied at once - docker would identify it as something has changed at each rebuild and would re-install the packages again.
# Therefore, since requirements.txt won't be changing much, it is always nice to copy and run installation separately.
# Rule of Thumb: Order Dockerfile from least-frequently-changing to most-frequently-changing.
