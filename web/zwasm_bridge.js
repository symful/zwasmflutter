/*
 * zwasm Flutter web bridge.
 *
 * Loads zwasm_plugin.wasm (wasm64-wasi) and exposes a flat API that mirrors
 * the native shim. Pointers are wasm64 (BigInt) inside the module; this file
 * converts them to JS numbers at the boundary and splits 64-bit values into
 * low/high 32-bit halves so Dart needs no BigInt interop.
 *
 * Include this file before flutter_bootstrap.js:
 *   <script src="assets/packages/zwasm/web/zwasm_bridge.js"></script>
 */
(function () {
  'use strict';

  var E = null;
  var output = '';
  var encoder = new TextEncoder();
  var decoder = new TextDecoder();

  function mem8() { return new Uint8Array(E.memory.buffer); }
  function dv() { return new DataView(E.memory.buffer); }
  function u32(p) { return dv().getUint32(Number(p), true); }
  function setU32(p, v) { dv().setUint32(Number(p), v >>> 0, true); }
  function setU64(p, v) {
    dv().setBigUint64(Number(p), BigInt.asUintN(64, BigInt(v)), true);
  }
  function getU64(p) { return dv().getBigUint64(Number(p), true); }
  function num(x) { return Number(x); }

  function alloc(len) { return num(E.zw_alloc(BigInt(len))); }
  function free(p, len) { E.zw_free(BigInt(p), BigInt(len)); }

  function allocBytes(bytes) {
    var p = alloc(bytes.length || 1);
    if (bytes.length) mem8().set(bytes, p);
    return p;
  }

  // ── WASI preview1 host ────────────────────────────────────────────────
  var wasi = {
    random_get: function (p, len) {
      var n = Number(len);
      crypto.getRandomValues(mem8().subarray(Number(p), Number(p) + n));
      return 0;
    },
    clock_time_get: function (id, precision, out) {
      void precision;
      var ns = Number(id) === 0
        ? BigInt(Date.now()) * 1000000n
        : BigInt(Math.round(performance.now() * 1000000));
      setU64(out, ns);
      return 0;
    },
    clock_res_get: function (id, out) {
      void id;
      setU64(out, 1000000n);
      return 0;
    },
    environ_sizes_get: function (countPtr, sizePtr) {
      setU32(countPtr, 0);
      setU32(sizePtr, 0);
      return 0;
    },
    environ_get: function () { return 0; },
    fd_write: function (fd, iovsPtr, iovsLen, writtenPtr) {
      var n = Number(iovsLen);
      var total = 0;
      var base = Number(iovsPtr);
      for (var i = 0; i < n; i++) {
        var buf = u32(base + i * 8);
        var len = u32(base + i * 8 + 4);
        if (len > 0) {
          var chunk = mem8().subarray(buf, buf + len);
          output += decoder.decode(chunk);
          total += len;
        }
      }
      if (fd === 1 || fd === 2) {
        // stdout/stderr: keep the text for the host, and mirror to console.
        if (typeof console !== 'undefined' && total > 0) {
          console.log(decoder.decode(mem8().subarray(u32(Number(iovsPtr)), u32(Number(iovsPtr)) + u32(Number(iovsPtr) + 4))));
        }
      }
      setU32(writtenPtr, total);
      return 0;
    },
    fd_read: function (fd, iovsPtr, iovsLen, readPtr) {
      void fd; void iovsPtr; void iovsLen;
      setU32(readPtr, 0);
      return 0;
    },
    fd_close: function () { return 0; },
    fd_sync: function () { return 0; },
    fd_seek: function (fd, offset, whence, out) {
      void fd; void offset; void whence;
      setU64(out, 0n);
      return 0;
    },
    fd_pread: function () { return 8; },
    fd_pwrite: function () { return 8; },
    fd_fdstat_get: function (fd, out) {
      void fd;
      var p = Number(out);
      mem8().fill(0, p, p + 24);
      mem8()[p] = 2; // character device
      setU64(p + 8, 0xFFFFFFFFFFFFFFFFn);
      setU64(p + 16, 0xFFFFFFFFFFFFFFFFn);
      return 0;
    },
    fd_filestat_get: function (fd, out) {
      void fd;
      var p = Number(out);
      mem8().fill(0, p, p + 64);
      return 0;
    },
    fd_filestat_set_times: function () { return 8; },
    fd_filestat_set_size: function () { return 8; },
    fd_readdir: function () { return 8; },
    poll_oneoff: function (inPtr, outPtr, nsubs, neventsPtr) {
      void inPtr; void outPtr; void nsubs;
      setU32(neventsPtr, 0);
      return 0;
    },
    path_open: function () { return 8; },
    path_create_directory: function () { return 8; },
    path_remove_directory: function () { return 8; },
    path_unlink_file: function () { return 8; },
    path_rename: function () { return 8; },
    path_link: function () { return 8; },
    path_symlink: function () { return 8; },
    path_readlink: function () { return 8; },
    path_filestat_get: function () { return 8; }
  };

  // ── host imports ───────────────────────────────────────────────────────
  var hostCallbacks = {};
  var nextHostCtx = 1;
  var instanceHostCtx = {};
  var instanceVfsCtx = {};

  function hostCall(ctx, index, argsPtr, nArgs, resultsPtr, nResults) {
    var cb = hostCallbacks[Number(ctx)];
    if (!cb) return 1;
    var n = Number(nArgs);
    var rn = Number(nResults);
    var args = new Uint32Array(E.memory.buffer, Number(argsPtr), n * 2);
    var out;
    try {
      out = cb(index, args);
    } catch (e) {
      return 1;
    }
    if (!out || out.length < rn * 2) return 1;
    for (var i = 0; i < rn; i++) {
      var lo = BigInt(out[i * 2] >>> 0);
      var hi = BigInt(out[i * 2 + 1] >>> 0);
      setU64(Number(resultsPtr) + i * 8, (hi << 32n) | lo);
    }
    return 0;
  }

  // ── VFS write-through ──────────────────────────────────────────────────
  var vfsCallbacks = {};
  var nextVfsCtx = 1;

  function vfsWrite(ctx, pathPtr, pathLen, offset, dataPtr, dataLen) {
    var cb = vfsCallbacks[Number(ctx)];
    if (!cb) return 1;
    var path = decoder.decode(
      new Uint8Array(E.memory.buffer, Number(pathPtr), Number(pathLen)));
    var data = new Uint8Array(
      E.memory.buffer, Number(dataPtr), Number(dataLen)).slice();
    try {
      cb(path, Number(offset), data);
      return 0;
    } catch (e) {
      return 1;
    }
  }

  function instanceSetVfsWriteCallback(instance, cb) {
    requireInit();
    if (!cb) {
      E.zw_instance_set_vfs_write_callback(BigInt(instance), 0n, 0n);
      var old = instanceVfsCtx[instance];
      if (old) delete vfsCallbacks[old];
      delete instanceVfsCtx[instance];
      return 0;
    }
    var ctx = nextVfsCtx++;
    vfsCallbacks[ctx] = cb;
    instanceVfsCtx[instance] = ctx;
    E.zw_instance_set_vfs_write_callback(
      BigInt(instance), BigInt(ctx), 1n);
    return 0;
  }

  function instanceNewWithImports(module, engine, fuel, maxPages, wasiConfig,
                                  modules, names, params, results, cb) {
    requireInit();
    var n = modules.length;
    if (n === 0) {
      return num(E.zw_instance_new(BigInt(module), engine, BigInt(fuel),
        BigInt(maxPages), wasiConfig ? BigInt(wasiConfig) : 0n));
    }
    var descs = alloc(n * 64);
    var blocks = [];
    function stage(bytes) {
      var p = allocBytes(bytes);
      blocks.push([p, bytes.length || 1]);
      return p;
    }
    for (var i = 0; i < n; i++) {
      var mb = encoder.encode(modules[i]);
      var nb = encoder.encode(names[i]);
      var mp = stage(mb);
      var np = stage(nb);
      var pp = stage(params[i]);
      var rp = stage(results[i]);
      var d = descs + i * 64;
      setU64(d, BigInt(mp));
      setU64(d + 8, BigInt(mb.length));
      setU64(d + 16, BigInt(np));
      setU64(d + 24, BigInt(nb.length));
      setU64(d + 32, BigInt(pp));
      setU64(d + 40, BigInt(params[i].length));
      setU64(d + 48, BigInt(rp));
      setU64(d + 56, BigInt(results[i].length));
    }
    var ctxId = nextHostCtx++;
    hostCallbacks[ctxId] = cb;
    var h = num(E.zw_instance_new_with_imports(
      BigInt(module), engine, BigInt(fuel), BigInt(maxPages),
      wasiConfig ? BigInt(wasiConfig) : 0n,
      BigInt(descs), n, BigInt(ctxId), 0n));
    if (!h) {
      delete hostCallbacks[ctxId];
    } else {
      instanceHostCtx[h] = ctxId;
    }
    for (var b = 0; b < blocks.length; b++) free(blocks[b][0], blocks[b][1]);
    free(descs, n * 64);
    return h;
  }

  async function init(bytes) {
    if (E) return;
    var result = await WebAssembly.instantiate(bytes, {
      wasi_snapshot_preview1: wasi,
      env: {
        zwJsHostCall: hostCall,
        zwJsVfsWrite: vfsWrite
      }
    });
    E = result.instance.exports;
  }

  function requireInit() {
    if (!E) throw new Error('zwasm: call ZwasmBridge.init() first');
  }

  function version() {
    requireInit();
    var len = num(E.zw_version_len());
    var p = num(E.zw_version());
    return decoder.decode(mem8().subarray(p, p + len));
  }

  function lastErrorMessage() {
    requireInit();
    var cap = 1024;
    var p = alloc(cap);
    var n = num(E.zw_last_error_message(BigInt(p), BigInt(cap)));
    var s = decoder.decode(mem8().subarray(p, p + n));
    free(p, cap);
    return s;
  }

  function moduleNew(engine, bytes) {
    requireInit();
    var len = bytes.length;
    var p = allocBytes(bytes);
    var h = E.zw_module_new(BigInt(engine), BigInt(p), BigInt(len));
    free(p, len || 1);
    return num(h);
  }

  function moduleExportName(module, index) {
    requireInit();
    var cap = 256;
    for (;;) {
      var p = alloc(cap);
      var full = num(E.zw_module_export_name(BigInt(module), index, BigInt(p), BigInt(cap)));
      var s = decoder.decode(mem8().subarray(p, p + Math.min(full, cap)));
      free(p, cap);
      if (full <= cap) return s;
      cap = full;
    }
  }

  function moduleImportText(fn, module, index) {
    requireInit();
    var cap = 256;
    for (;;) {
      var p = alloc(cap);
      var full = num(fn(BigInt(module), index, BigInt(p), BigInt(cap)));
      var s = decoder.decode(mem8().subarray(p, p + Math.min(full, cap)));
      free(p, cap);
      if (full <= cap) return s;
      cap = full;
    }
  }

  function moduleImportModule(module, index) {
    return moduleImportText(E.zw_module_import_module, module, index);
  }

  function moduleImportName(module, index) {
    return moduleImportText(E.zw_module_import_name, module, index);
  }

  function funcSig(instance, name) {
    requireInit();
    var nb = encoder.encode(name);
    var np = allocBytes(nb);
    var kinds = alloc(64);
    var counts = alloc(8);
    var rc = E.zw_instance_func_sig(
      BigInt(instance), BigInt(np), BigInt(nb.length),
      BigInt(kinds), BigInt(counts), BigInt(counts + 4));
    var params = u32(counts);
    var results = u32(counts + 4);
    var out = null;
    if (rc === 0) {
      out = new Uint32Array(2 + params + results);
      out[0] = params;
      out[1] = results;
      var m = mem8();
      for (var i = 0; i < params + results; i++) out[2 + i] = m[kinds + i];
    }
    free(np, nb.length || 1);
    free(kinds, 64);
    free(counts, 8);
    return out;
  }

  function invoke(instance, name, argsLo, argsHi) {
    requireInit();
    var sig = funcSig(instance, name);
    if (!sig) return new Uint32Array([4]);
    var nArgs = sig[0];
    var nRes = sig[1];
    // The shim rejects an arity mismatch; fail here without building buffers
    // when the Dart side and the export disagree, so undefined slots never
    // get read as zeros.
    if (argsLo.length !== nArgs || argsHi.length !== nArgs) {
      return new Uint32Array([5]);
    }
    var nb = encoder.encode(name);
    var np = allocBytes(nb);
    var ap = alloc(Math.max(nArgs, 1) * 8);
    var rp = alloc(Math.max(nRes, 1) * 8);
    for (var i = 0; i < nArgs; i++) {
      var v = (BigInt(argsHi[i] >>> 0) << 32n) | BigInt(argsLo[i] >>> 0);
      setU64(ap + i * 8, v);
    }
    var rc = num(E.zw_instance_invoke(
      BigInt(instance), BigInt(np), BigInt(nb.length),
      BigInt(ap), nArgs, BigInt(rp), nRes));
    var out = new Uint32Array(1 + nRes * 2);
    out[0] = rc;
    if (rc === 0) {
      for (var j = 0; j < nRes; j++) {
        var rv = getU64(rp + j * 8);
        out[1 + j * 2] = Number(rv & 0xFFFFFFFFn);
        out[2 + j * 2] = Number((rv >> 32n) & 0xFFFFFFFFn);
      }
    }
    free(np, nb.length || 1);
    free(ap, Math.max(nArgs, 1) * 8);
    free(rp, Math.max(nRes, 1) * 8);
    return out;
  }

  function globalGet(instance, name) {
    requireInit();
    var nb = encoder.encode(name);
    var np = allocBytes(nb);
    var out = alloc(8);
    var rc = num(E.zw_instance_global_get(BigInt(instance), BigInt(np), BigInt(nb.length), BigInt(out)));
    var v = rc === 0 ? getU64(out) : 0n;
    free(np, nb.length || 1);
    free(out, 8);
    return new Uint32Array([Number(v & 0xFFFFFFFFn), Number((v >> 32n) & 0xFFFFFFFFn)]);
  }

  function globalSet(instance, name, lo, hi) {
    requireInit();
    var nb = encoder.encode(name);
    var np = allocBytes(nb);
    var v = (BigInt(hi >>> 0) << 32n) | BigInt(lo >>> 0);
    var rc = num(E.zw_instance_global_set(BigInt(instance), BigInt(np), BigInt(nb.length), v));
    free(np, nb.length || 1);
    return rc;
  }

  function globalInfo(instance, name) {
    requireInit();
    var nb = encoder.encode(name);
    var np = allocBytes(nb);
    var out = alloc(2);
    var rc = num(E.zw_instance_global_info(BigInt(instance), BigInt(np), BigInt(nb.length), BigInt(out), BigInt(out + 1)));
    var result = null;
    if (rc === 0) result = new Uint8Array(mem8().subarray(out, out + 2));
    free(np, nb.length || 1);
    free(out, 2);
    return result;
  }

  function addArg(config, arg) {
    requireInit();
    var b = encoder.encode(arg);
    var p = allocBytes(b);
    E.zw_wasi_config_add_arg(BigInt(config), BigInt(p), BigInt(b.length));
    free(p, b.length || 1);
    return 0;
  }

  function addEnv(config, key, value) {
    requireInit();
    var kb = encoder.encode(key);
    var vb = encoder.encode(value);
    var kp = allocBytes(kb);
    var vp = allocBytes(vb);
    E.zw_wasi_config_add_env(BigInt(config), BigInt(kp), BigInt(kb.length), BigInt(vp), BigInt(vb.length));
    free(kp, kb.length || 1);
    free(vp, vb.length || 1);
    return 0;
  }

  function memoryBytes(instance) {
    requireInit();
    var p = num(E.zw_instance_memory_data(BigInt(instance)));
    var size = num(E.zw_instance_memory_size(BigInt(instance)));
    if (!p || !size) return new Uint8Array(0);
    return mem8().slice(p, p + size);
  }

  function memoryWrite(instance, address, data) {
    requireInit();
    var size = num(E.zw_instance_memory_size(BigInt(instance)));
    if (address < 0 || address + data.length > size) return 1;
    var p = num(E.zw_instance_memory_data(BigInt(instance)));
    mem8().set(data, p + address);
    return 0;
  }

  function addDir(config, path, writable) {
    requireInit();
    var b = encoder.encode(path);
    var p = allocBytes(b);
    var rc = num(E.zw_wasi_config_add_dir(BigInt(config), BigInt(p), BigInt(b.length), writable));
    free(p, b.length || 1);
    return rc;
  }

  function addFile(config, path, data, writable) {
    requireInit();
    var pb = encoder.encode(path);
    var pp = allocBytes(pb);
    var dp = allocBytes(data);
    var rc = num(E.zw_wasi_config_add_file(
      BigInt(config), BigInt(pp), BigInt(pb.length),
      BigInt(dp), BigInt(data.length), writable));
    free(pp, pb.length || 1);
    free(dp, data.length || 1);
    return rc;
  }

  function exportMount(instance, root) {
    requireInit();
    var rb = encoder.encode(root);
    var rp = allocBytes(rb);
    var need = num(E.zw_instance_export_mount(
      BigInt(instance), BigInt(rp), BigInt(rb.length), 0n, 0n));
    if (!need) {
      free(rp, rb.length || 1);
      return new Uint8Array(0);
    }
    var buf = alloc(need);
    E.zw_instance_export_mount(
      BigInt(instance), BigInt(rp), BigInt(rb.length), BigInt(buf), BigInt(need));
    var out = mem8().slice(buf, buf + need);
    free(buf, need);
    free(rp, rb.length || 1);
    return out;
  }

  function importMount(instance, root, data) {
    requireInit();
    var rb = encoder.encode(root);
    var rp = allocBytes(rb);
    var dp = allocBytes(data);
    var rc = num(E.zw_instance_import_mount(
      BigInt(instance), BigInt(rp), BigInt(rb.length),
      BigInt(dp), BigInt(data.length)));
    free(rp, rb.length || 1);
    free(dp, data.length || 1);
    return rc;
  }

  globalThis.ZwasmBridge = Object.freeze({
    // Bumped whenever the signatures or the globalThis shape changes. The
    // Dart web backend refuses to run against a different version.
    apiVersion: 6,
    abi: 'wasm64-wasi-interp',
    init: init,
    version: version,
    lastErrorCode: function () { requireInit(); return num(E.zw_last_error_code()); },
    lastErrorMessage: lastErrorMessage,

    engineNew: function () { requireInit(); return num(E.zw_engine_new()); },
    engineDelete: function (h) { requireInit(); E.zw_engine_delete(BigInt(h)); },

    moduleNew: moduleNew,
    moduleDelete: function (h) { requireInit(); E.zw_module_delete(BigInt(h)); },
    moduleExportCount: function (h) { requireInit(); return num(E.zw_module_export_count(BigInt(h))); },
    moduleExportKind: function (h, i) { requireInit(); return num(E.zw_module_export_kind(BigInt(h), i)); },
    moduleExportName: moduleExportName,

    moduleImportCount: function (h) { requireInit(); return num(E.zw_module_import_count(BigInt(h))); },
    moduleImportKind: function (h, i) { requireInit(); return num(E.zw_module_import_kind(BigInt(h), i)); },
    moduleImportModule: moduleImportModule,
    moduleImportName: moduleImportName,

    wasiConfigNew: function () { requireInit(); return num(E.zw_wasi_config_new()); },
    wasiConfigDelete: function (h) { requireInit(); E.zw_wasi_config_delete(BigInt(h)); },
    wasiConfigAddArg: addArg,
    wasiConfigAddEnv: addEnv,
    wasiConfigInheritStdio: function (h) { requireInit(); E.zw_wasi_config_inherit_stdio(BigInt(h)); },
    wasiConfigPreopenDir: function () {
      throw new Error('WASI preopens are not supported on web');
    },
    wasiConfigAddFile: addFile,
    wasiConfigAddDir: addDir,

    instanceNew: function (module, engine, fuel, maxPages, wasiConfig) {
      requireInit();
      return num(E.zw_instance_new(BigInt(module), engine, BigInt(fuel),
        BigInt(maxPages), wasiConfig ? BigInt(wasiConfig) : 0n));
    },
    instanceNewWithImports: instanceNewWithImports,
    instanceSetVfsWriteCallback: instanceSetVfsWriteCallback,
    instanceDelete: function (h) {
      requireInit();
      var hc = instanceHostCtx[h];
      if (hc) { delete hostCallbacks[hc]; delete instanceHostCtx[h]; }
      var vc = instanceVfsCtx[h];
      if (vc) { delete vfsCallbacks[vc]; delete instanceVfsCtx[h]; }
      E.zw_instance_delete(BigInt(h));
    },

    funcSig: funcSig,
    invoke: invoke,
    wasiExitCode: function (h) { requireInit(); return num(E.zw_instance_wasi_exit_code(BigInt(h))); },

    setFuel: function (h, fuel) { requireInit(); E.zw_instance_set_fuel(BigInt(h), BigInt(fuel)); },
    fuelRemaining: function (h) { requireInit(); return num(E.zw_instance_fuel_remaining(BigInt(h))); },
    setMemoryLimit: function (h, pages) { requireInit(); E.zw_instance_set_memory_limit(BigInt(h), BigInt(pages)); },
    interrupt: function (h) { requireInit(); E.zw_instance_interrupt(BigInt(h)); },
    clearInterrupt: function (h) { requireInit(); E.zw_instance_clear_interrupt(BigInt(h)); },

    memorySize: function (h) { requireInit(); return num(E.zw_instance_memory_size(BigInt(h))); },
    memoryPages: function (h) { requireInit(); return num(E.zw_instance_memory_pages(BigInt(h))); },
    memoryGrow: function (h, delta) { requireInit(); return num(E.zw_instance_memory_grow(BigInt(h), delta)); },
    memoryBytes: memoryBytes,
    memoryWrite: memoryWrite,
    exportMount: exportMount,
    importMount: importMount,

    globalInfo: globalInfo,
    globalGet: globalGet,
    globalSet: globalSet,

    takeOutput: function () { var s = output; output = ''; return s; }
  });
})();
