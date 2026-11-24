import { BookOpen, Bluetooth } from "lucide-react";
import type { MeasurementRun } from "../core";
export default function Guide({
  run,
  logs,
}: {
  run: MeasurementRun | null;
  logs: string[];
}) {
  return (
    <>
      <details id="guia">
        <summary>
          <BookOpen size={18} />
          Guía de práctica
        </summary>
        <div className="detail-body">
          <ol>
            <li>
              <strong>Prepara el patrón.</strong> Empieza por una resistencia
              conocida y después un circuito RC. Anota el valor nominal, la
              tolerancia y el montaje.
            </li>
            <li>
              <strong>Conecta.</strong> Enciende BioMess y cierra la conexión de
              la app móvil. Usa Chrome en Mac o Chrome/Edge en Windows, con
              Bluetooth activo. Comprueba serie y batería.
            </li>
            <li>
              <strong>Configura y mide.</strong> Empieza con 4 kHz–198 kHz, 48
              puntos y 5 repeticiones. Mantén la pestaña visible. La placa
              determina los parámetros efectivos.
            </li>
            <li>
              <strong>Interpreta.</strong> Z = R + jX, R = |Z| cos(φ), X = |Z|
              sin(φ). La fase se recibe en grados. Nyquist representa −X: una
              carga capacitiva aparece arriba.
            </li>
            <li>
              <strong>Compara.</strong> Repite cambiando longitud o disposición
              de cables. Compara módulo, fase y dispersión con el patrón. Una
              buena repetibilidad no demuestra exactitud.
            </li>
            <li>
              <strong>Documenta.</strong> Exporta CSV para cálculos y JSON para
              conservar configuración y fragmentos crudos. Los datos se
              mantienen en esta pestaña hasta que la cierres o recargues.
            </li>
          </ol>
          <p>
            El modo simulado usa una resistencia de 1 kΩ o un circuito Rs + (Rp
            ∥ C), con Rs = 100 Ω, Rp = 400 Ω y C = 10 nF, con variación
            determinista entre repeticiones. No es una calibración de la PCB. La
            práctica inicial se realiza con componentes de banco.
          </p>
          <p>
            La repetibilidad es el CV muestral de |Z| entre repeticiones para
            cada frecuencia; se muestra el máximo. Con una sola repetición no se
            puede estimar.
          </p>
        </div>
      </details>
      <details>
        <summary>
          <Bluetooth size={18} />
          Registro BLE y datos crudos
        </summary>
        <div className="detail-body">
          <p>
            Cada punto contiene 12 bytes: frecuencia, módulo y fase, como
            float32 little-endian. Los fragmentos BLE se concatenan antes de
            interpretar los puntos.
          </p>
          <pre>
            {logs.length
              ? logs.join("\n")
              : "Todavía no hay eventos de conexión."}
          </pre>
          {run && (
            <>
              <p>
                {run.source === "simulation"
                  ? "Simulación: no se han recibido notificaciones reales."
                  : `${run.rawChunks.length} fragmentos recibidos.`}{" "}
                El JSON incluye los bytes originales.
              </p>
              <pre className="bytes">
                {run.rawChunks
                  .slice(0, 8)
                  .map(
                    (c, i) =>
                      `${i + 1}: ${c.map((b) => b.toString(16).padStart(2, "0")).join(" ")}`,
                  )
                  .join("\n")}
              </pre>
            </>
          )}
        </div>
      </details>
    </>
  );
}
