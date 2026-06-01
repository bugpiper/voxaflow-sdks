package com.voxaflow.sdk

/** Error codes shared across all Voxa SDKs. Keep identical in concept everywhere. */
enum class VoxaErrorCode { AUTH, CAPABILITY, CONNECTION, DEVICE, MEDIA, SERVER }

/** Typed error surfaced by the SDK. Never contains PHI (transcript/message content). */
class VoxaException(
    val code: VoxaErrorCode,
    message: String,
    val status: Int? = null,
    cause: Throwable? = null,
) : Exception(message, cause)
