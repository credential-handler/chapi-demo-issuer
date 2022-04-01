FROM httpd:2.4
ARG MEDIATOR="authn.io"
ARG WALLET_HOST="chapi-demo-wallet.digitalbazaar.com"
COPY . /usr/local/apache2/htdocs/
RUN sed -i "s/authn.io/${MEDIATOR}/g" /usr/local/apache2/htdocs/config.js
RUN sed -i "s/chapi-demo-wallet.digitalbazaar.com/${WALLET_HOST}/g" /usr/local/apache2/htdocs/index.html
