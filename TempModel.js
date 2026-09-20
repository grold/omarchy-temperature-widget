// TempModel.js - Sensor parser and presentation model for Omarchy temperature widget

function toUnit(celsius, unit) {
  if (celsius === null || celsius === undefined || isNaN(celsius)) return null;
  return unit === "F" ? Math.round(celsius * 1.8 + 32) : Math.round(celsius);
}

function unitSuffix(unit) {
  return unit === "F" ? "°F" : "°C";
}

function formatValue(celsius, unit) {
  var v = toUnit(celsius, unit);
  return v !== null ? (v + unitSuffix(unit)) : "—";
}

function thermometerIcon(celsius) {
  if (celsius === null || celsius === undefined || isNaN(celsius)) return "\uf2cb";
  if (celsius < 50) return "\uf2cb";
  if (celsius < 65) return "\uf2ca";
  if (celsius < 75) return "\uf2c9";
  if (celsius < 85) return "\uf2c8";
  return "\uf2c7";
}

function statusLevel(celsius) {
  if (celsius === null || celsius === undefined || isNaN(celsius)) return "normal";
  if (celsius >= 85) return "critical";
  if (celsius >= 75) return "hot";
  if (celsius >= 65) return "warm";
  return "normal";
}

function statusLabel(celsius) {
  var s = statusLevel(celsius);
  switch (s) {
    case "critical": return "Critical";
    case "hot": return "High";
    case "warm": return "Warm";
    default: return "Normal";
  }
}

function parseSensors(rawText) {
  var data = {};
  try {
    data = JSON.parse(rawText || "{}");
  } catch (e) {
    return emptyModel();
  }

  var cpu = { temp: null, max: 100, crit: 100, label: "CPU", cores: [] };
  var gpu = null;
  var storage = [];
  var system = [];
  var allTemps = [];

  for (var chipName in data) {
    if (!data.hasOwnProperty(chipName)) continue;
    var chipData = data[chipName];
    if (!chipData || typeof chipData !== "object") continue;

    var lowerChip = chipName.toLowerCase();

    // 1. CPU detection
    if (lowerChip.indexOf("coretemp") !== -1 ||
        lowerChip.indexOf("k10temp") !== -1 ||
        lowerChip.indexOf("zenpower") !== -1 ||
        lowerChip.indexOf("cpu_thermal") !== -1) {

      for (var key in chipData) {
        if (!chipData.hasOwnProperty(key)) continue;
        var val = chipData[key];
        if (!val || typeof val !== "object") continue;

        var tempKey = findTempKey(val);
        if (!tempKey) continue;
        var t = parseFloat(val[tempKey]);
        if (isNaN(t)) continue;

        var maxVal = tempAttr(val, tempKey, "_max", 100);
        var critVal = tempAttr(val, tempKey, "_crit", 100);

        allTemps.push(t);

        if (key.indexOf("Package") !== -1 || key.indexOf("Tdie") !== -1 || key.indexOf("Tctl") !== -1) {
          cpu.temp = t;
          cpu.max = maxVal;
          cpu.crit = critVal;
        } else if (key.indexOf("Core") !== -1 || key.indexOf("Tccd") !== -1) {
          cpu.cores.push({ name: key, temp: t, max: maxVal, crit: critVal });
        } else {
          cpu.cores.push({ name: key, temp: t, max: maxVal, crit: critVal });
        }
      }

      if (cpu.temp === null && cpu.cores.length > 0) {
        var sum = 0;
        var maxCore = 0;
        for (var c = 0; c < cpu.cores.length; c++) {
          sum += cpu.cores[c].temp;
          if (cpu.cores[c].temp > maxCore) maxCore = cpu.cores[c].temp;
        }
        cpu.temp = Math.round(sum / cpu.cores.length);
      }
    }
    // 2. Storage (NVMe, drivetemp)
    else if (lowerChip.indexOf("nvme") !== -1 || lowerChip.indexOf("drivetemp") !== -1) {
      for (var skey in chipData) {
        if (!chipData.hasOwnProperty(skey)) continue;
        var sval = chipData[skey];
        if (!sval || typeof sval !== "object") continue;

        var stempKey = findTempKey(sval);
        if (!stempKey) continue;
        var st = parseFloat(sval[stempKey]);
        if (isNaN(st)) continue;

        var scrit = tempAttr(sval, stempKey, "_crit", 90);

        allTemps.push(st);
        storage.push({
          chip: chipName.split("-")[0].toUpperCase(),
          name: skey,
          temp: st,
          crit: scrit
        });
      }
    }
    // 3. GPU (AMDGPU, NVIDIA, Nouveau, Intel Arc/Xe)
    else if (lowerChip.indexOf("amdgpu") !== -1 ||
             lowerChip.indexOf("nvidia") !== -1 ||
             lowerChip.indexOf("nouveau") !== -1 ||
             lowerChip.indexOf("gpu") !== -1) {

      for (var gkey in chipData) {
        if (!chipData.hasOwnProperty(gkey)) continue;
        var gval = chipData[gkey];
        if (!gval || typeof gval !== "object") continue;

        var gtempKey = findTempKey(gval);
        if (!gtempKey) continue;
        var gt = parseFloat(gval[gtempKey]);
        if (isNaN(gt)) continue;

        var gcrit = tempAttr(gval, gtempKey, "_crit", 95);

        allTemps.push(gt);
        if (!gpu) gpu = { temp: gt, label: "GPU", max: 95, crit: gcrit, details: [] };
        gpu.details.push({ name: gkey, temp: gt, crit: gcrit });
        if (gt > gpu.temp) gpu.temp = gt;
      }
    }
    // 4. Motherboard / System / ACPI / Chipset
    else {
      var prefix = "System";
      if (lowerChip.indexOf("pch") !== -1) prefix = "Chipset (PCH)";
      else if (lowerChip.indexOf("acpitz") !== -1) prefix = "ACPI";
      else if (lowerChip.indexOf("it87") !== -1 || lowerChip.indexOf("nct6") !== -1) prefix = "Motherboard";

      for (var mkey in chipData) {
        if (!chipData.hasOwnProperty(mkey)) continue;
        var mval = chipData[mkey];
        if (!mval || typeof mval !== "object") continue;

        var mtempKey = findTempKey(mval);
        if (!mtempKey) continue;
        var mt = parseFloat(mval[mtempKey]);
        if (isNaN(mt)) continue;

        allTemps.push(mt);
        system.push({
          chip: prefix,
          name: mkey,
          temp: mt
        });
      }
    }
  }

  // Sort cores numerically
  cpu.cores.sort(function(a, b) {
    var numA = parseInt(a.name.replace(/\D/g, ""), 10) || 0;
    var numB = parseInt(b.name.replace(/\D/g, ""), 10) || 0;
    return numA - numB;
  });

  var maxTemp = allTemps.length > 0 ? Math.max.apply(null, allTemps) : 0;
  var primaryTemp = cpu.temp !== null ? cpu.temp : (gpu ? gpu.temp : maxTemp);

  return {
    cpu: cpu,
    gpu: gpu,
    storage: storage,
    system: system,
    maxTemp: maxTemp,
    primaryTemp: primaryTemp,
    hasData: allTemps.length > 0
  };
}

// lm-sensors groups every reading of a chip into one object, so a single entry
// can carry voltages (in0_input), currents (curr1_input) and fan speeds
// (fan1_input) next to temperatures. Matching a bare "_input" suffix picked
// those up and reported a 20 V USB-C rail as 20 C. Only temp*_input is a
// temperature.
function findTempKey(obj) {
  for (var k in obj) {
    if (obj.hasOwnProperty(k) && /^temp[0-9]*_input$/.test(k)) {
      return k;
    }
  }
  return null;
}

// Read a sibling attribute of the same sensor: temp2_input -> temp2_crit.
// Guards against borrowing fan1_max or in0_max from an unrelated reading.
function tempAttr(obj, tempKey, suffix, fallback) {
  var k = tempKey.replace(/_input$/, suffix);
  if (!obj.hasOwnProperty(k)) return fallback;
  var v = parseFloat(obj[k]);
  return isNaN(v) ? fallback : v;
}

function emptyModel() {
  return {
    cpu: { temp: null, max: 100, crit: 100, label: "CPU", cores: [] },
    gpu: null,
    storage: [],
    system: [],
    maxTemp: 0,
    primaryTemp: null,
    hasData: false
  };
}

function formatBarLabel(model, formatMode, unit) {
  if (!model || !model.hasData || model.primaryTemp === null) return "—";

  switch (formatMode) {
    case "cpu":
      return "CPU " + formatValue(model.primaryTemp, unit);
    case "multi":
      var res = "CPU " + toUnit(model.primaryTemp, unit) + "°";
      if (model.gpu && model.gpu.temp !== null) {
        res += " GPU " + toUnit(model.gpu.temp, unit) + "°";
      } else if (model.storage.length > 0 && model.storage[0].temp !== null) {
        res += " SSD " + toUnit(model.storage[0].temp, unit) + "°";
      }
      return res;
    case "max":
      return "Max " + formatValue(model.maxTemp, unit);
    case "compact":
    default:
      return formatValue(model.primaryTemp, unit);
  }
}

function formatTooltip(model, unit) {
  if (!model || !model.hasData) return "No temperature sensors detected";

  var lines = ["Hardware Temperatures:"];
  if (model.cpu.temp !== null) {
    var cpuLine = "• CPU: " + formatValue(model.cpu.temp, unit);
    if (model.cpu.cores.length > 0) {
      var coreStr = model.cpu.cores.map(function(c) {
        return c.name + ": " + toUnit(c.temp, unit) + "°";
      }).join(", ");
      cpuLine += " (" + coreStr + ")";
    }
    lines.push(cpuLine);
  }

  if (model.gpu && model.gpu.temp !== null) {
    lines.push("• GPU: " + formatValue(model.gpu.temp, unit));
  }

  if (model.storage.length > 0) {
    var storageStr = model.storage.map(function(s) {
      return s.chip + " " + s.name + ": " + formatValue(s.temp, unit);
    }).join(", ");
    lines.push("• Storage: " + storageStr);
  }

  if (model.system.length > 0) {
    var sysStr = model.system.map(function(s) {
      return s.chip + " " + s.name + ": " + formatValue(s.temp, unit);
    }).join(", ");
    lines.push("• System: " + sysStr);
  }

  lines.push("");
  lines.push("Left click: detailed monitor");
  lines.push("Right click: switch format");
  lines.push("Middle click: refresh");

  return lines.join("\n");
}

function nextFormat(current) {
  var modes = ["compact", "cpu", "multi", "max"];
  var idx = modes.indexOf(current);
  if (idx === -1 || idx === modes.length - 1) return modes[0];
  return modes[idx + 1];
}

function formatDisplayName(formatMode) {
  switch (formatMode) {
    case "cpu": return "CPU Temp (e.g. CPU 55°C)";
    case "multi": return "Multi-sensor (e.g. CPU 55° SSD 58°)";
    case "max": return "Maximum Temp (e.g. Max 60°C)";
    case "compact":
    default: return "Compact (e.g. 55°C)";
  }
}
