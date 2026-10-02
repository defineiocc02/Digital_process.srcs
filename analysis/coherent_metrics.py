"""Coherent ADC metrics with a single, explicit power partition.

Input is a real record with a known integer-bin fundamental. Units cancel in
ratios. DC is excluded; Nyquist is counted once; aliased harmonics are deduplicated.
These metrics describe the supplied final words, not analog or silicon accuracy.
"""
from __future__ import annotations
import math
import numpy as np

def coherent_metrics(codes, fs_hz: float, signal_bin: int, max_harmonic: int = 8):
    if np.iscomplexobj(codes):
        raise ValueError("A one-sided spectrum requires real input")
    x = np.asarray(codes, dtype=float)
    if x.ndim != 1 or x.size < 16 or not np.all(np.isfinite(x)):
        raise ValueError("Need at least 16 finite real samples")
    if not math.isfinite(fs_hz) or fs_hz <= 0:
        raise ValueError("Invalid sampling rate")
    n = x.size
    if not isinstance(signal_bin, (int, np.integer)) or not 0 < signal_bin < n/2:
        raise ValueError("Fundamental must be an interior integer FFT bin")
    if not isinstance(max_harmonic, (int, np.integer)) or max_harmonic < 2:
        raise ValueError("At least the second harmonic is required")
    power = np.abs(np.fft.rfft(x-x.mean()))**2/n**2
    power[1:-1 if n % 2 == 0 else None] *= 2
    signal = float(power[signal_bin])
    if signal <= 0 or not np.isfinite(signal):
        raise ValueError("Record has no measurable fundamental")
    harmonic_bins = set()
    for order in range(2, max_harmonic+1):
        alias = (order*signal_bin) % n
        alias = min(alias, n-alias)
        if alias not in (0, signal_bin):
            harmonic_bins.add(alias)
    residual_mask = np.ones(power.size, dtype=bool)
    residual_mask[[0, signal_bin]] = False
    noise_mask = residual_mask.copy()
    if harmonic_bins:
        noise_mask[list(harmonic_bins)] = False
    distortion = float(power[list(harmonic_bins)].sum()) if harmonic_bins else 0.0
    noise = float(power[noise_mask].sum())
    residual = noise + distortion
    spur = float(np.max(power[residual_mask]))
    def ratio(denominator):
        return math.inf if denominator == 0 else 10*math.log10(signal/denominator)
    sndr, snr = ratio(residual), ratio(noise)
    return {
        "sndr_db": sndr,
        "snr_db": snr,
        "sfdr_db": ratio(spur),
        "thd_db": -math.inf if distortion == 0 else 10*math.log10(distortion/signal),
        "enob": (sndr-1.76)/6.02,
    }
