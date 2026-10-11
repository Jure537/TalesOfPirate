#include "stdafx.h"
#include "ShaderLoader.h"

#include <cstdio>
#include <string>
#include <vector>


namespace Corsairs::Engine::Render {
	namespace {
		// Чтение файла целиком в out. На неуспех логирует и возвращает false.
		bool ReadWholeFile(std::string_view file,
						   std::string_view context,
						   std::vector<std::uint8_t>& out) {
			const std::string path{file};

			std::FILE* fp = std::fopen(path.c_str(), "rb");
			if (fp == nullptr) {
				ToLogService("errors", LogLevel::Error,
							 "[{}] fopen failed: file={}", context, path);
				return false;
			}

			std::fseek(fp, 0, SEEK_END);
			const long size = std::ftell(fp);
			std::fseek(fp, 0, SEEK_SET);

			if (size <= 0) {
				std::fclose(fp);
				ToLogService("errors", LogLevel::Error,
							 "[{}] empty/invalid file: file={}, size={}",
							 context, path, size);
				return false;
			}

			out.resize(static_cast<std::size_t>(size));
			const std::size_t read = std::fread(out.data(), 1, out.size(), fp);
			std::fclose(fp);

			if (read != out.size()) {
				ToLogService("errors", LogLevel::Error,
							 "[{}] short read: file={}, expected={}, got={}",
							 context, path, out.size(), read);
				return false;
			}

			return true;
		}
	} // namespace

	LW_RESULT ShaderLoader::LoadEffect(IDirect3DDeviceX* device,
									   std::string_view file,
									   ID3DXEffect** out_effect) {
		if (device == nullptr || out_effect == nullptr) {
			ToLogService("errors", LogLevel::Error,
						 "[ShaderLoader::LoadEffect] invalid args: device={}, out_effect={}",
						 static_cast<const void*>(device),
						 static_cast<const void*>(out_effect));
			return LW_RET_FAILED;
		}
		*out_effect = nullptr;

		std::vector<std::uint8_t> data;
		if (!ReadWholeFile(file, "ShaderLoader::LoadEffect", data)) {
			return LW_RET_FAILED;
		}

		ID3DXBuffer* err_buf = nullptr;
		HRESULT hr = D3DXCreateEffect(
			device,
			data.data(),
			static_cast<UINT>(data.size()),
			nullptr, // defines
			nullptr, // includes
			0, // flags
			nullptr, // pool
			out_effect,
			&err_buf);

		if (FAILED(hr)) {
			const char* err_msg = (err_buf && err_buf->GetBufferPointer())
									  ? static_cast<const char*>(err_buf->GetBufferPointer())
									  : "(no error buffer)";
			ToLogService("errors", LogLevel::Error,
						 "[ShaderLoader::LoadEffect] D3DXCreateEffect failed: file={}, hr=0x{:08X}, err={}",
						 file, static_cast<std::uint32_t>(hr), err_msg);
			LW_SAFE_RELEASE(err_buf);
			return LW_RET_FAILED;
		}

		LW_SAFE_RELEASE(err_buf);
		return LW_RET_OK;
	}

	LW_RESULT ShaderLoader::CompileVertexShader(std::string_view file,
												const D3DXMACRO* defines,
												ID3DXBuffer** out_code) {
		if (out_code == nullptr) {
			ToLogService("errors", LogLevel::Error,
						 "[ShaderLoader::CompileVertexShader] invalid args: out_code is null");
			return LW_RET_FAILED;
		}
		*out_code = nullptr;

		std::vector<std::uint8_t> data;
		if (!ReadWholeFile(file, "ShaderLoader::CompileVertexShader", data)) {
			return LW_RET_FAILED;
		}

		// Массив `D3DXMACRO` обязан быть терминирован {NULL, NULL}; пустой
		// массив (defines->Name == nullptr) трактуется как «макросов нет».
		const D3DXMACRO* macro_ptr = nullptr;
		if (defines != nullptr && defines->Name != nullptr) {
			macro_ptr = defines;
		}

		ID3DXBuffer* err_buf = nullptr;
		// The engine uses fixed-function pixel processing (no pixel shader).
		// Hardware vs_3_0 requires a matching ps_3_0; vs_2_0 preserves the
		// legacy texture-stage, alpha and lighting pipeline.
		HRESULT hr = D3DXCompileShader(
			reinterpret_cast<LPCSTR>(data.data()),
			data.size(),
			macro_ptr,
			nullptr, // includes
			"main",
			"vs_2_0",
			0, // compile_flag
			out_code,
			&err_buf,
			nullptr); // const-table out

		if (FAILED(hr)) {
			const char* err_msg = (err_buf && err_buf->GetBufferPointer())
									  ? static_cast<const char*>(err_buf->GetBufferPointer())
									  : "(no error buffer)";
			ToLogService("errors", LogLevel::Error,
						 "[ShaderLoader::CompileVertexShader] D3DXCompileShader failed: file={}, size={}, hr=0x{:08X}, err={}",
						 file, data.size(), static_cast<std::uint32_t>(hr), err_msg);
			LW_SAFE_RELEASE(err_buf);
			return LW_RET_FAILED;
		}

		LW_SAFE_RELEASE(err_buf);
		return LW_RET_OK;
	}
} // namespace Corsairs::Engine::Render
