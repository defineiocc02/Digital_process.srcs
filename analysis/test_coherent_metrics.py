"""Analytical controls independent of the ADC model and historical metric tool."""
import math
import numpy as np
import pytest
from analysis.coherent_metrics import coherent_metrics

def test_known_noise_and_harmonic_partition():
    n=4096
    t=np.arange(n)
    x=np.sin(2*np.pi*127*t/n)+0.01*np.sin(2*np.pi*381*t/n)+0.001*np.sin(2*np.pi*631*t/n)
    result=coherent_metrics(x,1e6,127)
    assert result["snr_db"] == pytest.approx(60,abs=1e-8)
    assert result["thd_db"] == pytest.approx(-40,abs=1e-8)
    assert result["sfdr_db"] == pytest.approx(40,abs=1e-8)
    assert result["sndr_db"] == pytest.approx(10*math.log10(1/(1e-4+1e-6)),abs=1e-8)
    assert result["snr_db"] >= result["sndr_db"]
    shifted=coherent_metrics(x+100,1e6,127)
    assert shifted == pytest.approx(result,abs=1e-8)

def test_nyquist_power_is_not_doubled():
    n=4096
    t=np.arange(n)
    x=np.sin(2*np.pi*127*t/n)+0.01*np.cos(np.pi*t)
    result=coherent_metrics(x,1e6,127)
    assert result["sndr_db"] == pytest.approx(10*math.log10(0.5/0.0001),abs=1e-8)

@pytest.mark.parametrize("n",[2048,2049])
def test_quantized_ideal_control_and_power_order(n):
    t=np.arange(n)
    x=np.rint(32766*np.sin(2*np.pi*71*t/n+0.123))
    result=coherent_metrics(x,5e6,71)
    assert 97.5 < result["sndr_db"] < 98.7
    assert result["snr_db"] >= result["sndr_db"]

def test_alias_harmonics_are_not_counted_twice():
    n=4096
    t=np.arange(n)
    x=np.sin(2*np.pi*512*t/n)+0.01*np.cos(2*np.pi*1024*t/n)
    result=coherent_metrics(x,1e6,512,max_harmonic=16)
    assert result["sndr_db"] == pytest.approx(40,abs=1e-8)
    assert result["thd_db"] == pytest.approx(-40,abs=1e-8)

@pytest.mark.parametrize("x",[np.zeros(32),np.full(32,np.nan),np.ones((2,32)),np.ones(32,dtype=complex)])
def test_invalid_records_are_rejected(x):
    with pytest.raises(ValueError):
        coherent_metrics(x,1e6,3)
