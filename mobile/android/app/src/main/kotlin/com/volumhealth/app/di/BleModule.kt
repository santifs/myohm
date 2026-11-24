package com.volumhealth.app.di

import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

@Module
@InstallIn(SingletonComponent::class)
abstract class BleModule {
    // BioMessBleManager is provided directly via @Inject constructor
    // No additional bindings needed
}
