"""Prevent corrected metrics from silently reusing historical cached values."""
import json
import subprocess
import sys
from dataclasses import replace
from pathlib import Path
import pytest
from .run_campaign import FullSarConfig, campaign_identity, _load_checkpoint, _write_checkpoint

def test_legacy_and_changed_configuration_cannot_resume(tmp_path):
    path = tmp_path / "checkpoint.json"
    path.write_text(json.dumps({"metrics": [], "trace": {}}))
    identity = campaign_identity(FullSarConfig(n_chips=1))
    with pytest.raises(ValueError, match="provenance"):
        _load_checkpoint(path, identity)
    _write_checkpoint(path, 0, [], {}, identity)
    assert _load_checkpoint(path, identity) == ([], {})
    other = campaign_identity(replace(FullSarConfig(n_chips=1), seed=9))
    with pytest.raises(ValueError, match="provenance"):
        _load_checkpoint(path, other)

def test_documented_direct_script_entrypoint():
    script = Path(__file__).with_name("run_campaign.py")
    result = subprocess.run([sys.executable, str(script), "--help"], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert "--no-resume" in result.stdout
