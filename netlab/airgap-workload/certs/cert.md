
## Gerar PKI interna

```
mkdir -p ./demolab-certs
cd ./demolab-certs
umask 077
```

## Chave privada da CA raiz

```
openssl genrsa -out demolab-root-ca.key.pem 4096
```

## Certificado da CA raiz, válido por 10 anos

```
openssl req -x509 -new -sha256 \
  -key demolab-root-ca.key.pem \
  -out demolab-root-ca.cert.pem \
  -days 3650 \
  -subj "/C=BR/O=ME Lab/CN=ME Lab Root CA" \
  -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -addext "subjectKeyIdentifier=hash"
```

## Chave privada do webserver

```
openssl genrsa -out appdemo.eroicloud.com.br.key.pem 3072
```

## CSR com CN e SAN

```
openssl req -new -sha256 \
  -key appdemo.eroicloud.com.br.key.pem \
  -out appdemo.eroicloud.com.br.csr.pem \
  -subj "/C=BR/O=ME Lab/CN=appdemo.eroicloud.com.br" \
  -addext "subjectAltName=DNS:appdemo.eroicloud.com.br"

```

## Crie as extensões do certificado webserver


```
cat > appdemo.eroicloud.com.br.ext <<'EOF'
authorityKeyIdentifier=keyid,issuer
subjectKeyIdentifier=hash
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:appdemo.eroicloud.com.br
EOF
```


## Assine o certificado com a CA raiz

```
openssl x509 -req -sha256 \
  -in appdemo.eroicloud.com.br.csr.pem \
  -CA demolab-root-ca.cert.pem \
  -CAkey demolab-root-ca.key.pem \
  -CAcreateserial \
  -out appdemo.eroicloud.com.br.cert.pem \
  -days 825 \
  -extfile appdemo.eroicloud.com.br.ext
```


## Valide a cadeia e o hostname


```
openssl verify \
  -CAfile demolab-root-ca.cert.pem \
  appdemo.eroicloud.com.br.cert.pem

openssl x509 \
  -in appdemo.eroicloud.com.br.cert.pem \
  -checkhost appdemo.eroicloud.com.br \
  -noout
```


## Exportar certificado para PFX

```
openssl pkcs12 -export \
  -out appdemo.eroicloud.com.br.pfx \
  -inkey appdemo.eroicloud.com.br.key.pem \
  -in appdemo.eroicloud.com.br.cert.pem \
  -certfile demolab-root-ca.cert.pem \
  -name "appdemo.eroicloud.com.br"
```

## Versao DER

```
openssl x509 \
  -in appdemo.eroicloud.com.br.cert.pem \
  -outform pem \
  -out appdemo.eroicloud.com.br.cer
```

```
openssl x509 \
  -in demolab-root-ca.cert.pem \
  -outform pem \
  -out demolab-root-ca.cer
```


## Validar

```
  openssl pkcs12 \
  -in appdemo.eroicloud.com.br.pfx \
  -info \
  -noout
```

```
openssl x509 \
  -in appdemo.eroicloud.com.br.cert.pem \
  -noout \
  -subject \
  -issuer \
  -dates \
  -ext subjectAltName
```