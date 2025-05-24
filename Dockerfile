# Usar una imagen base de Node.js LTS
FROM node:20-alpine

# Establecer el directorio de trabajo en el contenedor
WORKDIR /usr/src/app

# Copiar el package.json y package-lock.json (si existiera)
# Copiamos package.json primero para aprovechar el cache de Docker si no cambia
COPY package*.json ./

# Instalar dependencias de producción
RUN npm install --only=production

# Copiar el resto del código de la aplicación (server.js, y la carpeta public si se sirve desde aquí)
# Si 'public' se sirve a través de un servicio estático separado en Render, no necesita estar en esta imagen.
# Pero si este servicio Node.js también sirve los archivos estáticos, entonces sí.
# Nuestro server.js actual está configurado para servir desde una carpeta 'public' local.
COPY . .

# Exponer el puerto en el que la aplicación escucha.
# Nuestro server.js usa process.env.PORT || 3005. Render seteará process.env.PORT.
# EXPOSE debe coincidir con el puerto que la aplicación *dentro* del contenedor escucha.
EXPOSE 3005

# Comando para ejecutar la aplicación
# El package.json ya tiene "start": "node server.js"
CMD [ "npm", "start" ]