package com.volumhealth.core.database.util

import com.volumhealth.core.model.BatteryData
import com.volumhealth.core.model.ColeParameters
import com.volumhealth.core.model.ContactQuality
import com.volumhealth.core.model.ConvergenceMetrics
import com.volumhealth.core.model.DeviceInfo
import com.volumhealth.core.model.FrequencyResponseQuality
import com.volumhealth.core.model.Gender
import com.volumhealth.core.model.ImpedanceData
import com.volumhealth.core.model.InterferenceLevel
import com.volumhealth.core.model.MeasurementPoint
import com.volumhealth.core.model.MeasurementType
import com.volumhealth.core.model.ParameterErrors
import com.volumhealth.core.model.PatientSnapshot
import com.volumhealth.core.model.ProcessingTier
import com.volumhealth.core.model.QualityMetrics
import com.volumhealth.core.model.QuaternionData
import com.volumhealth.core.model.SignalQuality
import com.volumhealth.core.model.StabilityMetrics
import kotlinx.datetime.Instant
import org.json.JSONArray
import org.json.JSONObject

internal object Serialization {
    fun encodeImpedance(data: ImpedanceData): String = impedanceToJson(data).toString()
    fun decodeImpedance(value: String): ImpedanceData = jsonToImpedance(JSONObject(value))

    fun encodePatientSnapshot(snapshot: PatientSnapshot?): String? = snapshot?.let { patientSnapshotToJson(it).toString() }
    fun decodePatientSnapshot(value: String?): PatientSnapshot? = value?.let { jsonToPatientSnapshot(JSONObject(it)) }

    fun encodeColeParameters(params: ColeParameters?): String? = params?.let { coleParametersToJson(it).toString() }
    fun decodeColeParameters(value: String?): ColeParameters? = value?.let { jsonToColeParameters(JSONObject(it)) }

    private fun impedanceToJson(data: ImpedanceData): JSONObject {
        val json = JSONObject()
        json.put("timestamp", data.timestamp.toEpochMilliseconds())
        data.deviceInfo?.let { json.put("device", deviceInfoToJson(it)) }
        val reps = JSONArray()
        data.repetitions.forEach { repetition ->
            val repArray = JSONArray()
            repetition.forEach { point ->
                val obj = JSONObject()
                obj.put("frequency", point.frequency.toDouble())
                obj.put("magnitude", point.magnitude.toDouble())
                obj.put("phase", point.phase.toDouble())
                repArray.put(obj)
            }
            reps.put(repArray)
        }
        json.put("repetitions", reps)
        return json
    }

    private fun jsonToImpedance(json: JSONObject): ImpedanceData {
        val timestamp = Instant.fromEpochMilliseconds(json.getLong("timestamp"))
        val device = json.optJSONObject("device")?.let { jsonToDeviceInfo(it) }
        val repsJson = json.getJSONArray("repetitions")
        val reps = mutableListOf<List<MeasurementPoint>>()
        for (i in 0 until repsJson.length()) {
            val repArray = repsJson.getJSONArray(i)
            val points = mutableListOf<MeasurementPoint>()
            for (j in 0 until repArray.length()) {
                val pointObj = repArray.getJSONObject(j)
                points.add(
                    MeasurementPoint(
                        frequency = pointObj.getDouble("frequency").toFloat(),
                        magnitude = pointObj.getDouble("magnitude").toFloat(),
                        phase = pointObj.getDouble("phase").toFloat()
                    )
                )
            }
            reps.add(points)
        }
        return ImpedanceData(repetitions = reps, timestamp = timestamp, deviceInfo = device)
    }

    private fun deviceInfoToJson(info: DeviceInfo): JSONObject {
        val obj = JSONObject()
        obj.put("name", info.name)
        obj.put("serial", info.serialNumber)
        info.batteryLevel?.let {
            val battery = JSONObject()
            battery.put("voltage", it.voltageMillivolts.toInt())
            battery.put("percentage", it.percentage.toInt())
            obj.put("battery", battery)
        }
        info.quaternion?.let { obj.put("quaternion", quaternionToJson(it)) }
        info.quaternionVariance?.let { obj.put("quaternionVariance", quaternionToJson(it)) }
        return obj
    }

    private fun jsonToDeviceInfo(obj: JSONObject): DeviceInfo {
        val name = obj.optString("name", "")
        val serial = obj.optString("serial", null)
        val battery = obj.optJSONObject("battery")?.let {
            BatteryData(
                voltageMillivolts = it.getInt("voltage").toUShort(),
                percentage = it.getInt("percentage").toUShort()
            )
        }
        val quaternion = obj.optJSONObject("quaternion")?.let { jsonToQuaternion(it) }
        val quaternionVariance = obj.optJSONObject("quaternionVariance")?.let { jsonToQuaternion(it) }
        return DeviceInfo(
            name = name,
            serialNumber = serial,
            batteryLevel = battery,
            quaternion = quaternion,
            quaternionVariance = quaternionVariance
        )
    }

    private fun quaternionToJson(quaternion: QuaternionData): JSONObject {
        val obj = JSONObject()
        obj.put("w", quaternion.w.toDouble())
        obj.put("x", quaternion.x.toDouble())
        obj.put("y", quaternion.y.toDouble())
        obj.put("z", quaternion.z.toDouble())
        return obj
    }

    private fun jsonToQuaternion(obj: JSONObject): QuaternionData {
        return QuaternionData(
            w = obj.getDouble("w").toFloat(),
            x = obj.getDouble("x").toFloat(),
            y = obj.getDouble("y").toFloat(),
            z = obj.getDouble("z").toFloat()
        )
    }

    private fun patientSnapshotToJson(snapshot: PatientSnapshot): JSONObject {
        val obj = JSONObject()
        obj.put("name", snapshot.name)
        obj.put("exerciseName", snapshot.exerciseName)
        obj.put("measurementNumber", snapshot.measurementNumber)
        obj.put("age", snapshot.age)
        obj.put("gender", snapshot.gender.name)
        obj.put("height", snapshot.height.toDouble())
        obj.put("weight", snapshot.weight.toDouble())
        obj.put("bmi", snapshot.bmi.toDouble())
        obj.put("timestamp", snapshot.timestamp.toEpochMilliseconds())
        return obj
    }

    private fun jsonToPatientSnapshot(obj: JSONObject): PatientSnapshot {
        return PatientSnapshot(
            name = obj.getString("name"),
            exerciseName = obj.getString("exerciseName"),
            measurementNumber = obj.getInt("measurementNumber"),
            age = obj.getInt("age"),
            gender = Gender.valueOf(obj.getString("gender")),
            height = obj.getDouble("height").toFloat(),
            weight = obj.getDouble("weight").toFloat(),
            bmi = obj.getDouble("bmi").toFloat(),
            timestamp = Instant.fromEpochMilliseconds(obj.getLong("timestamp"))
        )
    }

    private fun coleParametersToJson(params: ColeParameters): JSONObject {
        val obj = JSONObject()
        obj.put("Re", params.Re.toDouble())
        obj.put("Ri", params.Ri.toDouble())
        obj.put("Cm", params.Cm.toDouble())
        obj.put("fc", params.fc.toDouble())
        obj.put("alpha", params.alpha.toDouble())
        obj.put("error", params.error.toDouble())
        obj.put("tier", params.processingTier.name)
        obj.put("measurementType", params.measurementType.name)
        obj.put("timestamp", params.timestamp.toEpochMilliseconds())
        obj.put("quality", qualityToJson(params.quality))
        params.patient?.let { obj.put("patient", patientSnapshotToJson(it)) }
        params.rawData?.let { obj.put("rawData", impedanceToJson(it)) }
        return obj
    }

    private fun jsonToColeParameters(obj: JSONObject): ColeParameters {
        return ColeParameters(
            Re = obj.getDouble("Re").toFloat(),
            Ri = obj.getDouble("Ri").toFloat(),
            Cm = obj.getDouble("Cm").toFloat(),
            fc = obj.getDouble("fc").toFloat(),
            alpha = obj.getDouble("alpha").toFloat(),
            error = obj.getDouble("error").toFloat(),
            processingTier = ProcessingTier.valueOf(obj.getString("tier")),
            quality = jsonToQuality(obj.getJSONObject("quality")),
            patient = obj.optJSONObject("patient")?.let { jsonToPatientSnapshot(it) },
            measurementType = MeasurementType.valueOf(obj.getString("measurementType")),
            rawData = obj.optJSONObject("rawData")?.let { jsonToImpedance(it) },
            timestamp = Instant.fromEpochMilliseconds(obj.getLong("timestamp"))
        )
    }

    private fun qualityToJson(quality: QualityMetrics): JSONObject {
        val obj = JSONObject()
        obj.put("score", quality.score.toDouble())
        obj.put("contactQuality", contactQualityToJson(quality.contactQuality))
        obj.put("signalQuality", signalQualityToJson(quality.signalQuality))
        obj.put("convergence", convergenceToJson(quality.convergence))
        obj.put("stability", stabilityToJson(quality.stabilityMetrics))
        return obj
    }

    private fun jsonToQuality(obj: JSONObject): QualityMetrics {
        return QualityMetrics(
            score = obj.getDouble("score").toFloat(),
            contactQuality = jsonToContactQuality(obj.getJSONObject("contactQuality")),
            signalQuality = jsonToSignalQuality(obj.getJSONObject("signalQuality")),
            convergence = jsonToConvergence(obj.getJSONObject("convergence")),
            stabilityMetrics = jsonToStability(obj.getJSONObject("stability"))
        )
    }

    private fun contactQualityToJson(contact: ContactQuality): JSONObject {
        val obj = JSONObject()
        obj.put("electrodeImpedance", contact.electrodeImpedance.toDouble())
        obj.put("mismatchPercentage", contact.mismatchPercentage.toDouble())
        return obj
    }

    private fun jsonToContactQuality(obj: JSONObject): ContactQuality {
        return ContactQuality(
            electrodeImpedance = obj.getDouble("electrodeImpedance").toFloat(),
            mismatchPercentage = obj.getDouble("mismatchPercentage").toFloat()
        )
    }

    private fun signalQualityToJson(signal: SignalQuality): JSONObject {
        val obj = JSONObject()
        obj.put("snr", signal.snr.toDouble())
        obj.put("phaseStability", signal.phaseStability.toDouble())
        obj.put("frequencyResponse", signal.frequencyResponse.name)
        return obj
    }

    private fun jsonToSignalQuality(obj: JSONObject): SignalQuality {
        return SignalQuality(
            snr = obj.getDouble("snr").toFloat(),
            phaseStability = obj.getDouble("phaseStability").toFloat(),
            frequencyResponse = FrequencyResponseQuality.valueOf(obj.getString("frequencyResponse"))
        )
    }

    private fun convergenceToJson(convergence: ConvergenceMetrics): JSONObject {
        val obj = JSONObject()
        obj.put("iterations", convergence.iterations)
        obj.put("residualError", convergence.residualError?.toDouble() ?: JSONObject.NULL)
        obj.put("converged", convergence.converged)
        obj.put("parameterErrors", convergence.parameterErrors?.let(::parameterErrorsToJson) ?: JSONObject.NULL)
        return obj
    }

    private fun jsonToConvergence(obj: JSONObject): ConvergenceMetrics {
        return ConvergenceMetrics(
            iterations = obj.getInt("iterations"),
            residualError = if (obj.isNull("residualError")) null else obj.getDouble("residualError").toFloat(),
            converged = obj.getBoolean("converged"),
            parameterErrors = obj.optJSONObject("parameterErrors")?.let(::jsonToParameterErrors)
        )
    }

    private fun parameterErrorsToJson(errors: ParameterErrors): JSONObject {
        val obj = JSONObject()
        obj.put("re", errors.reError.toDouble())
        obj.put("ri", errors.riError.toDouble())
        obj.put("cm", errors.cmError.toDouble())
        obj.put("fc", errors.fcError.toDouble())
        obj.put("alpha", errors.alphaError.toDouble())
        return obj
    }

    private fun jsonToParameterErrors(obj: JSONObject): ParameterErrors {
        return ParameterErrors(
            reError = obj.getDouble("re").toFloat(),
            riError = obj.getDouble("ri").toFloat(),
            cmError = obj.getDouble("cm").toFloat(),
            fcError = obj.getDouble("fc").toFloat(),
            alphaError = obj.getDouble("alpha").toFloat()
        )
    }

    private fun stabilityToJson(stability: StabilityMetrics): JSONObject {
        val obj = JSONObject()
        obj.put("movementDetected", stability.movementDetected)
        obj.put("quaternionStability", stability.quaternionStability.toDouble())
        obj.put("impedanceStability", stability.impedanceStability.toDouble())
        obj.put("interference", stability.interferenceLevel.name)
        return obj
    }

    private fun jsonToStability(obj: JSONObject): StabilityMetrics {
        return StabilityMetrics(
            movementDetected = obj.getBoolean("movementDetected"),
            quaternionStability = obj.getDouble("quaternionStability").toFloat(),
            impedanceStability = obj.getDouble("impedanceStability").toFloat(),
            interferenceLevel = InterferenceLevel.valueOf(obj.getString("interference"))
        )
    }
}
