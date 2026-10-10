#pragma once

#include "lwDirectX.h"
#include "lwErrorCode.h"

#include <string_view>


namespace Corsairs::Engine::Render {

// Единая точка загрузки и компиляции шейдеров MindPower3D.
//   • LoadEffect          — .fx через D3DXCreateEffect (in-memory, после ReadWholeFile).
//   • CompileVertexShader — vertex-shader HLSL через D3DXCompileShader (vs_2_0).
//
// Stateless, все методы — static. Ошибки логируются в "errors" с
// префиксом file:line / err-buffer'ом D3DX. Возвращают LW_RESULT
// (LW_RET_OK / LW_RET_FAILED) — без бросков.
//
// На неуспех out_*-указатели остаются nullptr; владение успешно
// возвращёнными COM-объектами (`ID3DXEffect`, `ID3DXBuffer`) — за
// caller'ом, освобождать через `Release()`.
class ShaderLoader {
public:
	[[nodiscard]] static LW_RESULT LoadEffect(IDirect3DDeviceX* device,
											  std::string_view file,
											  ID3DXEffect** out_effect);

	// `defines` — массив `D3DXMACRO`, терминированный {NULL, NULL}.
	// Допускается nullptr (без макросов).
	[[nodiscard]] static LW_RESULT CompileVertexShader(std::string_view file,
													   const D3DXMACRO* defines,
													   ID3DXBuffer** out_code);
};

} // namespace Corsairs::Engine::Render
