package fx

import "core:strings"

import D3D11 "vendor:directx/d3d11"
import D3D "vendor:directx/d3d_compiler"

font_hlsl := #load("font.hlsl")
font_png : []u8 = #load("font.png")
font_texture : Texture
font_shader: ^D3D11.IPixelShader

Character :: struct {
    advance: f32,

    left   : f32,
    bottom : f32,
    right  : f32,
    top    : f32,

    left_uv   : f32,
    bottom_uv : f32,
    right_uv  : f32,
    top_uv    : f32,

    width  : f32,
    height : f32,
}

// See and of this file for more details
default_font : [512]Character = {
    32 = Character{advance = 0.28125, left = 0, bottom = -0, right = 0, top = -0, left_uv = 0, bottom_uv = 1, right_uv = 0, top_uv = 1, width = 0, height = 0},
    33 = Character{advance = 0.28759766, left = 0.037548829, bottom = -0.77812499, right = 0.25004882, top = 0.059374999, left_uv = 0.79448533, bottom_uv = 0.17316176, right_uv = 0.81948525, top_uv = 0.27169117, width = 0.21249999, height = 0.83749998},
    34 = Character{advance = 0.4658203, left = 0.06416015, bottom = -0.77812499, right = 0.40166014, top = -0.409375, left_uv = 0.95257354, bottom_uv = 0.4194853, right_uv = 0.9922794, top_uv = 0.46286765, width = 0.33749998, height = 0.36874998},
    35 = Character{advance = 0.63330078, left = -0.02446289, bottom = -0.77812499, right = 0.6567871, top = 0.059374999, left_uv = 0.088602945, bottom_uv = 0.30551469, right_uv = 0.16875, top_uv = 0.40404412, width = 0.68124998, height = 0.83749998},
    36 = Character{advance = 0.64160156, left = 0.011425781, bottom = -0.87187499, right = 0.63017577, top = 0.153125, left_uv = 0.26874998, bottom_uv = 0.0077205878, right_uv = 0.34154412, top_uv = 0.12830883, width = 0.61874998, height = 1.02499998},
    37 = Character{advance = 0.98193359, left = 0.072216794, bottom = -0.77812499, right = 0.90971678, top = 0.059374999, left_uv = 0.18419117, bottom_uv = 0.30551469, right_uv = 0.2827206, top_uv = 0.40404412, width = 0.83749998, height = 0.83749998},
    38 = Character{advance = 0.64404297, left = 0.014599609, bottom = -0.77812499, right = 0.6645996, top = 0.059374999, left_uv = 0.91580886, bottom_uv = 0.17316176, right_uv = 0.9922794, top_uv = 0.27169117, width = 0.64999998, height = 0.83749998},
    39 = Character{advance = 0.29980469, left = 0.059277344, bottom = -0.77812499, right = 0.24052735, top = -0.409375, left_uv = 0.8753677, bottom_uv = 0.8753677, right_uv = 0.89669114, top_uv = 0.91874999, width = 0.18125, height = 0.36874998},
    40 = Character{advance = 0.36474609, left = 0.0746582, bottom = -0.80937499, right = 0.34965819, top = 0.184375, left_uv = 0.77242649, bottom_uv = 0.0077205878, right_uv = 0.8047794, top_uv = 0.124632359, width = 0.27499998, height = 0.99374998},
    41 = Character{advance = 0.36474609, left = 0.01508789, bottom = -0.80937499, right = 0.29008788, top = 0.184375, left_uv = 0.82022059, bottom_uv = 0.0077205878, right_uv = 0.8525735, top_uv = 0.124632359, width = 0.27499998, height = 0.99374998},
    42 = Character{advance = 0.50097656, left = 0.019238282, bottom = -0.77812499, right = 0.48173827, top = -0.284375, left_uv = 0.6584559, bottom_uv = 0.8753677, right_uv = 0.7128676, top_uv = 0.93345588, width = 0.46249998, height = 0.49374998},
    43 = Character{advance = 0.66162109, left = 0.052685548, bottom = -0.55937499, right = 0.60893553, top = -0.003125, left_uv = 0.57757354, bottom_uv = 0.8753677, right_uv = 0.64301467, top_uv = 0.94080883, width = 0.55624998, height = 0.55624998},
    44 = Character{advance = 0.28808594, left = 0.028027344, bottom = -0.153125, right = 0.24052735, top = 0.215625, left_uv = 0.95992649, bottom_uv = 0.6915441, right_uv = 0.98492646, top_uv = 0.73492646, width = 0.2125, height = 0.36875},
    45 = Character{advance = 0.45996094, left = 0.029980469, bottom = -0.40312499, right = 0.42998046, top = -0.221875, left_uv = 0.08492647, bottom_uv = 0.96727943, right_uv = 0.1319853, top_uv = 0.98860294, width = 0.39999998, height = 0.18124999},
    46 = Character{advance = 0.28808594, left = 0.037792969, bottom = -0.184375, right = 0.25029296, top = 0.059374999, left_uv = 0.95257354, bottom_uv = 0.47830886, right_uv = 0.9775735, top_uv = 0.50698525, width = 0.21249999, height = 0.24375},
    47 = Character{advance = 0.36035156, left = -0.019824218, bottom = -0.80937499, right = 0.38017577, top = 0.153125, left_uv = 0.220955878, bottom_uv = 0.17316176, right_uv = 0.2680147, top_uv = 0.28639707, width = 0.39999998, height = 0.96249998},
    48 = Character{advance = 0.63085938, left = 0.021679688, bottom = -0.77812499, right = 0.60917968, top = 0.059374999, left_uv = 0.65477943, bottom_uv = 0.30551469, right_uv = 0.72389704, top_uv = 0.40404412, width = 0.58749998, height = 0.83749998},
    49 = Character{advance = 0.40673828, left = 0.0141113279, bottom = -0.77812499, right = 0.35161132, top = 0.059374999, left_uv = 0.73933828, bottom_uv = 0.30551469, right_uv = 0.77904409, top_uv = 0.40404412, width = 0.33749998, height = 0.83749998},
    50 = Character{advance = 0.60986328, left = 0.028759766, bottom = -0.77812499, right = 0.58500975, top = 0.059374999, left_uv = 0.79448533, bottom_uv = 0.30551469, right_uv = 0.85992646, top_uv = 0.40404412, width = 0.55624998, height = 0.83749998},
    51 = Character{advance = 0.61767578, left = 0.015820313, bottom = -0.77812499, right = 0.6033203, top = 0.059374999, left_uv = 0.0077205878, bottom_uv = 0.4194853, right_uv = 0.07683823, top_uv = 0.51801467, width = 0.58749998, height = 0.83749998},
    52 = Character{advance = 0.64599609, left = 0.0141113279, bottom = -0.77812499, right = 0.6328613, top = 0.059374999, left_uv = 0.09227941, bottom_uv = 0.4194853, right_uv = 0.165073529, top_uv = 0.51801467, width = 0.61874998, height = 0.83749998},
    53 = Character{advance = 0.5932617, left = 0.019970704, bottom = -0.77812499, right = 0.57622069, top = 0.059374999, left_uv = 0.180514708, bottom_uv = 0.4194853, right_uv = 0.24595588, top_uv = 0.51801467, width = 0.55624998, height = 0.83749998},
    54 = Character{advance = 0.62011719, left = 0.016308594, bottom = -0.77812499, right = 0.60380858, top = 0.059374999, left_uv = 0.26139706, bottom_uv = 0.4194853, right_uv = 0.3305147, top_uv = 0.51801467, width = 0.58749998, height = 0.83749998},
    55 = Character{advance = 0.56591797, left = 0.004833984, bottom = -0.77812499, right = 0.56108397, top = 0.059374999, left_uv = 0.34595588, bottom_uv = 0.4194853, right_uv = 0.41139707, top_uv = 0.51801467, width = 0.55624998, height = 0.83749998},
    56 = Character{advance = 0.61865234, left = 0.0155761717, bottom = -0.77812499, right = 0.60307616, top = 0.059374999, left_uv = 0.42683822, bottom_uv = 0.4194853, right_uv = 0.49595585, top_uv = 0.51801467, width = 0.58749998, height = 0.83749998},
    57 = Character{advance = 0.62011719, left = 0.016308594, bottom = -0.77812499, right = 0.60380858, top = 0.059374999, left_uv = 0.51139706, bottom_uv = 0.4194853, right_uv = 0.58051467, top_uv = 0.51801467, width = 0.58749998, height = 0.83749998},
    58 = Character{advance = 0.28808594, left = 0.037792969, bottom = -0.55937499, right = 0.25029296, top = 0.059374999, left_uv = 0.53713238, bottom_uv = 0.8753677, right_uv = 0.56213236, top_uv = 0.9481617, width = 0.21249999, height = 0.61874998},
    59 = Character{advance = 0.3017578, left = 0.021191407, bottom = -0.55937499, right = 0.26494139, top = 0.215625, left_uv = 0.20257352, bottom_uv = 0.76139706, right_uv = 0.23125, top_uv = 0.8525735, width = 0.24374999, height = 0.77499998},
    60 = Character{advance = 0.66162109, left = 0.052929688, bottom = -0.59062499, right = 0.57792968, top = 0.028124999, left_uv = 0.38272059, bottom_uv = 0.8753677, right_uv = 0.4444853, top_uv = 0.9481617, width = 0.52499998, height = 0.61874998},
    61 = Character{advance = 0.66162109, left = 0.068554685, bottom = -0.46562499, right = 0.59355468, top = -0.096874997, left_uv = 0.7981618, bottom_uv = 0.8753677, right_uv = 0.85992646, top_uv = 0.91874999, width = 0.52499998, height = 0.36874998},
    62 = Character{advance = 0.66162109, left = 0.0836914, bottom = -0.59062499, right = 0.60869139, top = 0.028124999, left_uv = 0.45992646, bottom_uv = 0.8753677, right_uv = 0.52169114, top_uv = 0.9481617, width = 0.52499998, height = 0.61874998},
    63 = Character{advance = 0.51123047, left = 0.0038574219, bottom = -0.77812499, right = 0.4976074, top = 0.059374999, left_uv = 0.88639706, bottom_uv = 0.64742649, right_uv = 0.94448525, top_uv = 0.74595588, width = 0.49374998, height = 0.83749998},
    64 = Character{advance = 0.9658203, left = 0.017285157, bottom = -0.74687499, right = 0.94853514, top = 0.246875, left_uv = 0.86801475, bottom_uv = 0.0077205878, right_uv = 0.9775735, top_uv = 0.124632359, width = 0.93124998, height = 0.99374998},
    65 = Character{advance = 0.6899414, left = -0.011279297, bottom = -0.77812499, right = 0.70122069, top = 0.059374999, left_uv = 0.78713238, bottom_uv = 0.64742649, right_uv = 0.87095588, top_uv = 0.74595588, width = 0.71249998, height = 0.83749998},
    66 = Character{advance = 0.65429688, left = 0.049023438, bottom = -0.77812499, right = 0.6365234, top = 0.059374999, left_uv = 0.9231618, bottom_uv = 0.5334559, right_uv = 0.9922794, top_uv = 0.63198525, width = 0.58749998, height = 0.83749998},
    67 = Character{advance = 0.73046875, left = 0.027050782, bottom = -0.77812499, right = 0.70830077, top = 0.059374999, left_uv = 0.61433828, bottom_uv = 0.64742649, right_uv = 0.69448525, top_uv = 0.74595588, width = 0.68124998, height = 0.83749998},
    68 = Character{advance = 0.72167969, left = 0.05, bottom = -0.77812499, right = 0.69999999, top = 0.059374999, left_uv = 0.52242649, bottom_uv = 0.64742649, right_uv = 0.59889704, top_uv = 0.74595588, width = 0.64999998, height = 0.83749998},
    69 = Character{advance = 0.6010742, left = 0.049267579, bottom = -0.77812499, right = 0.57426757, top = 0.059374999, left_uv = 0.44522059, bottom_uv = 0.64742649, right_uv = 0.50698525, top_uv = 0.74595588, width = 0.52499998, height = 0.83749998},
    70 = Character{advance = 0.59033203, left = 0.045361329, bottom = -0.77812499, right = 0.5703613, top = 0.059374999, left_uv = 0.36801469, bottom_uv = 0.64742649, right_uv = 0.4297794, top_uv = 0.74595588, width = 0.52499998, height = 0.83749998},
    71 = Character{advance = 0.74609375, left = 0.015332031, bottom = -0.77812499, right = 0.727832, top = 0.059374999, left_uv = 0.26874998, bottom_uv = 0.64742649, right_uv = 0.35257354, top_uv = 0.74595588, width = 0.71249998, height = 0.83749998},
    72 = Character{advance = 0.74316406, left = 0.046582032, bottom = -0.77812499, right = 0.696582, top = 0.059374999, left_uv = 0.17683823, bottom_uv = 0.64742649, right_uv = 0.25330883, top_uv = 0.74595588, width = 0.64999998, height = 0.83749998},
    73 = Character{advance = 0.26855469, left = 0.043652344, bottom = -0.77812499, right = 0.22490235, top = 0.059374999, left_uv = 0.95625, bottom_uv = 0.30551469, right_uv = 0.9775735, top_uv = 0.40404412, width = 0.18125, height = 0.83749998},
    74 = Character{advance = 0.57080078, left = 0.0033691407, bottom = -0.77812499, right = 0.5283691, top = 0.059374999, left_uv = 0.70992649, bottom_uv = 0.64742649, right_uv = 0.77169114, top_uv = 0.74595588, width = 0.52499998, height = 0.83749998},
    75 = Character{advance = 0.671875, left = 0.056591798, bottom = -0.77812499, right = 0.67534178, top = 0.059374999, left_uv = 0.0077205878, bottom_uv = 0.64742649, right_uv = 0.080514707, top_uv = 0.74595588, width = 0.61874998, height = 0.83749998},
    76 = Character{advance = 0.56542969, left = 0.055859376, bottom = -0.77812499, right = 0.54960936, top = 0.059374999, left_uv = 0.84963238, bottom_uv = 0.5334559, right_uv = 0.90772057, top_uv = 0.63198525, width = 0.49374998, height = 0.83749998},
    77 = Character{advance = 0.9033203, left = 0.048535157, bottom = -0.77812499, right = 0.85478514, top = 0.059374999, left_uv = 0.73933828, bottom_uv = 0.5334559, right_uv = 0.83419114, top_uv = 0.63198525, width = 0.80624998, height = 0.83749998},
    78 = Character{advance = 0.75341797, left = 0.051708985, bottom = -0.77812499, right = 0.70170897, top = 0.059374999, left_uv = 0.64742649, bottom_uv = 0.5334559, right_uv = 0.72389704, top_uv = 0.63198525, width = 0.64999998, height = 0.83749998},
    79 = Character{advance = 0.76464844, left = 0.026074219, bottom = -0.77812499, right = 0.7385742, top = 0.059374999, left_uv = 0.5481618, bottom_uv = 0.5334559, right_uv = 0.63198525, top_uv = 0.63198525, width = 0.71249998, height = 0.83749998},
    80 = Character{advance = 0.63867188, left = 0.042675782, bottom = -0.77812499, right = 0.63017577, top = 0.059374999, left_uv = 0.46360293, bottom_uv = 0.5334559, right_uv = 0.53272057, top_uv = 0.63198525, width = 0.58749998, height = 0.83749998},
    81 = Character{advance = 0.76464844, left = 0.026074219, bottom = -0.77812499, right = 0.7385742, top = 0.121875, left_uv = 0.34595588, bottom_uv = 0.17316176, right_uv = 0.4297794, top_uv = 0.27904412, width = 0.71249998, height = 0.89999998},
    82 = Character{advance = 0.64355469, left = 0.041210938, bottom = -0.77812499, right = 0.6599609, top = 0.059374999, left_uv = 0.28345588, bottom_uv = 0.5334559, right_uv = 0.35625002, top_uv = 0.63198525, width = 0.61874998, height = 0.83749998},
    83 = Character{advance = 0.64160156, left = 0.011425781, bottom = -0.77812499, right = 0.63017577, top = 0.059374999, left_uv = 0.19522059, bottom_uv = 0.5334559, right_uv = 0.2680147, top_uv = 0.63198525, width = 0.61874998, height = 0.83749998},
    84 = Character{advance = 0.6455078, left = 0.013378906, bottom = -0.77812499, right = 0.63212889, top = 0.059374999, left_uv = 0.10698529, bottom_uv = 0.5334559, right_uv = 0.17977943, top_uv = 0.63198525, width = 0.61874998, height = 0.83749998},
    85 = Character{advance = 0.7441406, left = 0.047070313, bottom = -0.77812499, right = 0.6970703, top = 0.059374999, left_uv = 0.37169117, bottom_uv = 0.5334559, right_uv = 0.44816178, top_uv = 0.63198525, width = 0.64999998, height = 0.83749998},
    86 = Character{advance = 0.6899414, left = -0.011279297, bottom = -0.77812499, right = 0.70122069, top = 0.059374999, left_uv = 0.0077205878, bottom_uv = 0.5334559, right_uv = 0.091544114, top_uv = 0.63198525, width = 0.71249998, height = 0.83749998},
    87 = Character{advance = 0.98535156, left = -0.019824218, bottom = -0.77812499, right = 1.0051758, top = 0.059374999, left_uv = 0.0077205878, bottom_uv = 0.76139706, right_uv = 0.12830883, top_uv = 0.85992646, width = 1.0250001, height = 0.83749998},
    88 = Character{advance = 0.6821289, left = -0.015185547, bottom = -0.77812499, right = 0.69731444, top = 0.059374999, left_uv = 0.85330886, bottom_uv = 0.4194853, right_uv = 0.93713236, top_uv = 0.51801467, width = 0.71249998, height = 0.83749998},
    89 = Character{advance = 0.67871094, left = -0.01689453, bottom = -0.77812499, right = 0.69560546, top = 0.059374999, left_uv = 0.7540441, bottom_uv = 0.4194853, right_uv = 0.8378676, top_uv = 0.51801467, width = 0.71249998, height = 0.83749998},
    90 = Character{advance = 0.62890625, left = 0.020703126, bottom = -0.77812499, right = 0.6082031, top = 0.059374999, left_uv = 0.66948533, bottom_uv = 0.4194853, right_uv = 0.73860294, top_uv = 0.51801467, width = 0.58749998, height = 0.83749998},
    91 = Character{advance = 0.36474609, left = 0.070019528, bottom = -0.80937499, right = 0.34501952, top = 0.184375, left_uv = 0.0077205878, bottom_uv = 0.17316176, right_uv = 0.040073529, top_uv = 0.29007354, width = 0.27499998, height = 0.99374998},
    92 = Character{advance = 0.36035156, left = -0.019824218, bottom = -0.80937499, right = 0.38017577, top = 0.153125, left_uv = 0.28345588, bottom_uv = 0.17316176, right_uv = 0.3305147, top_uv = 0.28639707, width = 0.39999998, height = 0.96249998},
    93 = Character{advance = 0.36474609, left = 0.019726563, bottom = -0.80937499, right = 0.29472655, top = 0.184375, left_uv = 0.114338234, bottom_uv = 0.17316176, right_uv = 0.146691188, top_uv = 0.29007354, width = 0.27499998, height = 0.99374998},
    94 = Character{advance = 0.4711914, left = 0.0043457029, bottom = -0.74687499, right = 0.46684569, top = -0.346875, left_uv = 0.72830886, bottom_uv = 0.8753677, right_uv = 0.78272057, top_uv = 0.92242646, width = 0.46249998, height = 0.39999998},
    95 = Character{advance = 0.45605469, left = -0.034472656, bottom = -0.059374999, right = 0.49052733, top = 0.121875, left_uv = 0.0077205878, bottom_uv = 0.96727943, right_uv = 0.06948529, top_uv = 0.98860294, width = 0.52499998, height = 0.18125},
    96 = Character{advance = 0.3227539, left = 0.03461914, bottom = -0.80937499, right = 0.27836913, top = -0.565625, left_uv = 0.95992649, bottom_uv = 0.64742649, right_uv = 0.98860294, top_uv = 0.67610294, width = 0.24374999, height = 0.24374998},
    97 = Character{advance = 0.56152344, left = 0.0016601563, bottom = -0.59062499, right = 0.52666014, top = 0.059374999, left_uv = 0.82389706, bottom_uv = 0.76139706, right_uv = 0.8856617, top_uv = 0.8378676, width = 0.52499998, height = 0.64999998},
    98 = Character{advance = 0.61230469, left = 0.041210938, bottom = -0.77812499, right = 0.5974609, top = 0.059374999, left_uv = 0.095955886, bottom_uv = 0.64742649, right_uv = 0.16139707, top_uv = 0.74595588, width = 0.55624998, height = 0.83749998},
    99 = Character{advance = 0.57128906, left = 0.0084960936, bottom = -0.59062499, right = 0.56474608, top = 0.059374999, left_uv = 0.90110296, bottom_uv = 0.76139706, right_uv = 0.96654409, top_uv = 0.8378676, width = 0.55624998, height = 0.64999998},
    100 = Character{advance = 0.61230469, left = 0.0148437498, bottom = -0.77812499, right = 0.57109374, top = 0.059374999, left_uv = 0.8753677, bottom_uv = 0.30551469, right_uv = 0.94080883, top_uv = 0.40404412, width = 0.55624998, height = 0.83749998},
    101 = Character{advance = 0.5830078, left = 0.0143554686, bottom = -0.59062499, right = 0.57060546, top = 0.059374999, left_uv = 0.0077205878, bottom_uv = 0.8753677, right_uv = 0.073161766, top_uv = 0.9518382, width = 0.55624998, height = 0.64999998},
    102 = Character{advance = 0.37011719, left = -0.033496093, bottom = -0.80937499, right = 0.39775389, top = 0.059374999, left_uv = 0.60698533, bottom_uv = 0.17316176, right_uv = 0.65772057, top_uv = 0.27536765, width = 0.43124998, height = 0.86874998},
    103 = Character{advance = 0.61328125, left = 0.015332031, bottom = -0.59062499, right = 0.571582, top = 0.27812499, left_uv = 0.6731618, bottom_uv = 0.17316176, right_uv = 0.73860294, top_uv = 0.27536765, width = 0.55624998, height = 0.86874998},
    104 = Character{advance = 0.59130859, left = 0.033154298, bottom = -0.77812499, right = 0.55815428, top = 0.059374999, left_uv = 0.57757354, bottom_uv = 0.30551469, right_uv = 0.6393382, top_uv = 0.40404412, width = 0.52499998, height = 0.83749998},
    105 = Character{advance = 0.2421875, left = 0.0155761717, bottom = -0.80937499, right = 0.22807617, top = 0.059374999, left_uv = 0.7540441, bottom_uv = 0.17316176, right_uv = 0.77904409, top_uv = 0.27536765, width = 0.2125, height = 0.86874998},
    106 = Character{advance = 0.2421875, left = -0.05253906, bottom = -0.80937499, right = 0.22246094, top = 0.246875, left_uv = 0.121691175, bottom_uv = 0.0077205878, right_uv = 0.15404412, top_uv = 0.1319853, width = 0.275, height = 1.05624998},
    107 = Character{advance = 0.5488281, left = 0.043652344, bottom = -0.77812499, right = 0.56865233, top = 0.059374999, left_uv = 0.33492646, bottom_uv = 0.30551469, right_uv = 0.39669117, top_uv = 0.40404412, width = 0.52499998, height = 0.83749998},
    108 = Character{advance = 0.2421875, left = 0.03046875, bottom = -0.77812499, right = 0.21171875, top = 0.059374999, left_uv = 0.29816177, bottom_uv = 0.30551469, right_uv = 0.3194853, top_uv = 0.40404412, width = 0.18125, height = 0.83749998},
    109 = Character{advance = 0.87597656, left = 0.034863282, bottom = -0.59062499, right = 0.84111327, top = 0.059374999, left_uv = 0.59227943, bottom_uv = 0.76139706, right_uv = 0.68713236, top_uv = 0.8378676, width = 0.80624998, height = 0.64999998},
    110 = Character{advance = 0.5908203, left = 0.032910157, bottom = -0.59062499, right = 0.55791014, top = 0.059374999, left_uv = 0.24669117, bottom_uv = 0.76139706, right_uv = 0.30845588, top_uv = 0.8378676, width = 0.52499998, height = 0.64999998},
    111 = Character{advance = 0.59960938, left = 0.0060546873, bottom = -0.59062499, right = 0.59355468, top = 0.059374999, left_uv = 0.088602945, bottom_uv = 0.8753677, right_uv = 0.1577206, top_uv = 0.9518382, width = 0.58749998, height = 0.64999998},
    112 = Character{advance = 0.61230469, left = 0.041210938, bottom = -0.59062499, right = 0.5974609, top = 0.246875, left_uv = 0.0077205878, bottom_uv = 0.30551469, right_uv = 0.073161766, top_uv = 0.40404412, width = 0.55624998, height = 0.83749998},
    113 = Character{advance = 0.61230469, left = 0.0148437498, bottom = -0.59062499, right = 0.57109374, top = 0.246875, left_uv = 0.83492649, bottom_uv = 0.17316176, right_uv = 0.9003676, top_uv = 0.27169117, width = 0.55624998, height = 0.83749998},
    114 = Character{advance = 0.37646484, left = 0.031201173, bottom = -0.59062499, right = 0.39995116, top = 0.059374999, left_uv = 0.24669117, bottom_uv = 0.8753677, right_uv = 0.29007354, top_uv = 0.9518382, width = 0.36874998, height = 0.64999998},
    115 = Character{advance = 0.52783203, left = 0.01850586, bottom = -0.59062499, right = 0.51225585, top = 0.059374999, left_uv = 0.17316176, bottom_uv = 0.8753677, right_uv = 0.23125, top_uv = 0.9518382, width = 0.49374998, height = 0.64999998},
    116 = Character{advance = 0.32714844, left = -0.025927734, bottom = -0.71562499, right = 0.34282225, top = 0.059374999, left_uv = 0.14375, bottom_uv = 0.76139706, right_uv = 0.187132359, top_uv = 0.8525735, width = 0.36874998, height = 0.77499998},
    117 = Character{advance = 0.59130859, left = 0.033154298, bottom = -0.59062499, right = 0.55815428, top = 0.059374999, left_uv = 0.30551469, bottom_uv = 0.8753677, right_uv = 0.3672794, top_uv = 0.9518382, width = 0.52499998, height = 0.64999998},
    118 = Character{advance = 0.5620117, left = -0.0127441408, bottom = -0.59062499, right = 0.57475585, top = 0.059374999, left_uv = 0.70257354, bottom_uv = 0.76139706, right_uv = 0.77169114, top_uv = 0.8378676, width = 0.58749998, height = 0.64999998},
    119 = Character{advance = 0.81835938, left = -0.0095703127, bottom = -0.59062499, right = 0.82792968, top = 0.059374999, left_uv = 0.32389706, bottom_uv = 0.76139706, right_uv = 0.42242649, top_uv = 0.8378676, width = 0.83749998, height = 0.64999998},
    120 = Character{advance = 0.54589844, left = -0.0051757814, bottom = -0.59062499, right = 0.5510742, top = 0.059374999, left_uv = 0.43786764, bottom_uv = 0.76139706, right_uv = 0.50330883, top_uv = 0.8378676, width = 0.55624998, height = 0.64999998},
    121 = Character{advance = 0.5620117, left = -0.0127441408, bottom = -0.59062499, right = 0.57475585, top = 0.246875, left_uv = 0.49301472, bottom_uv = 0.30551469, right_uv = 0.56213236, top_uv = 0.40404412, width = 0.58749998, height = 0.83749998},
    122 = Character{advance = 0.55224609, left = 0.029248048, bottom = -0.59062499, right = 0.52299803, top = 0.059374999, left_uv = 0.51875, bottom_uv = 0.76139706, right_uv = 0.5768382, top_uv = 0.8378676, width = 0.49374998, height = 0.64999998},
    123 = Character{advance = 0.42626953, left = 0.033886719, bottom = -0.80937499, right = 0.4026367, top = 0.184375, left_uv = 0.16213235, bottom_uv = 0.17316176, right_uv = 0.20551471, top_uv = 0.29007354, width = 0.36874998, height = 0.99374998},
    124 = Character{advance = 0.33251953, left = 0.09125976, bottom = -0.99687499, right = 0.241259769, top = 0.27812499, left_uv = 0.0077205878, bottom_uv = 0.0077205878, right_uv = 0.025367647, top_uv = 0.1577206, width = 0.15, height = 1.27499998},
    125 = Character{advance = 0.42626953, left = 0.023632813, bottom = -0.80937499, right = 0.3923828, top = 0.184375, left_uv = 0.055514708, bottom_uv = 0.17316176, right_uv = 0.098897055, top_uv = 0.29007354, width = 0.36874998, height = 0.99374998},
    126 = Character{advance = 0.66162109, left = 0.03706003, bottom = -0.43437499, right = 0.62456006, top = -0.159375, left_uv = 0.91213238, bottom_uv = 0.8753677, right_uv = 0.98124999, top_uv = 0.90772057, width = 0.58750004, height = 0.27499998},
    199 = Character{advance = 0.73046875, left = 0.027050782, bottom = -0.77812499, right = 0.70830077, top = 0.246875, left_uv = 0.48566177, bottom_uv = 0.0077205878, right_uv = 0.56580883, top_uv = 0.12830883, width = 0.68124998, height = 1.02499998},
    214 = Character{advance = 0.76464844, left = 0.026074219, bottom = -0.96562499, right = 0.7385742, top = 0.059374999, left_uv = 0.58125, bottom_uv = 0.0077205878, right_uv = 0.6650735, top_uv = 0.12830883, width = 0.71249998, height = 1.02499998},
    220 = Character{advance = 0.7441406, left = 0.047070313, bottom = -0.96562499, right = 0.6970703, top = 0.059374999, left_uv = 0.68051475, bottom_uv = 0.0077205878, right_uv = 0.75698525, top_uv = 0.12830883, width = 0.64999998, height = 1.02499998},
    231 = Character{advance = 0.57128906, left = 0.0084960936, bottom = -0.59062499, right = 0.56474608, top = 0.246875, left_uv = 0.41213235, bottom_uv = 0.30551469, right_uv = 0.4775735, top_uv = 0.40404412, width = 0.55624998, height = 0.83749998},
    246 = Character{advance = 0.59960938, left = 0.0060546873, bottom = -0.80937499, right = 0.59355468, top = 0.059374999, left_uv = 0.52242649, bottom_uv = 0.17316176, right_uv = 0.59154409, top_uv = 0.27536765, width = 0.58749998, height = 0.86874998},
    252 = Character{advance = 0.59130859, left = 0.033154298, bottom = -0.80937499, right = 0.55815428, top = 0.059374999, left_uv = 0.44522059, bottom_uv = 0.17316176, right_uv = 0.50698525, top_uv = 0.27536765, width = 0.52499998, height = 0.86874998},
    286 = Character{advance = 0.74609375, left = 0.015332031, bottom = -0.99687499, right = 0.727832, top = 0.059374999, left_uv = 0.16948529, bottom_uv = 0.0077205878, right_uv = 0.25330883, top_uv = 0.1319853, width = 0.71249998, height = 1.05624998},
    287 = Character{advance = 0.61328125, left = 0.015332031, bottom = -0.80937499, right = 0.571582, top = 0.27812499, left_uv = 0.040808827, bottom_uv = 0.0077205878, right_uv = 0.106249996, top_uv = 0.13566177, width = 0.55624998, height = 1.08749998},
    304 = Character{advance = 0.26855469, left = 0.028271485, bottom = -0.96562499, right = 0.24077149, top = 0.059374999, left_uv = 0.44522059, bottom_uv = 0.0077205878, right_uv = 0.4702206, top_uv = 0.12830883, width = 0.2125, height = 1.02499998},
    305 = Character{advance = 0.2421875, left = 0.03046875, bottom = -0.59062499, right = 0.21171875, top = 0.059374999, left_uv = 0.78713238, bottom_uv = 0.76139706, right_uv = 0.80845588, top_uv = 0.8378676, width = 0.18125, height = 0.64999998},
    350 = Character{advance = 0.64160156, left = 0.011425781, bottom = -0.77812499, right = 0.63017577, top = 0.246875, left_uv = 0.3569853, bottom_uv = 0.0077205878, right_uv = 0.4297794, top_uv = 0.12830883, width = 0.61874998, height = 1.02499998},
    351 = Character{advance = 0.52783203, left = 0.01850586, bottom = -0.59062499, right = 0.51225585, top = 0.246875, left_uv = 0.5959559, bottom_uv = 0.4194853, right_uv = 0.65404409, top_uv = 0.51801467, width = 0.49374998, height = 0.83749998},
}

init_font :: proc() {
    // Takes 200 ms at startup maybe use qoi instead
    font_texture = load_texture_from_bytes(font_png)

	ps_blob: ^D3D11.IBlob
	D3D.Compile(raw_data(font_hlsl), len(font_hlsl), "font.hlsl", nil, nil, "ps_main", "ps_5_0", 0, 0, &ps_blob, nil)
	assert(ps_blob != nil)

	device->CreatePixelShader(ps_blob->GetBufferPointer(), ps_blob->GetBufferSize(), nil, &font_shader)
}

draw_char :: proc(char: int, x, y, size: f32, color: Color) -> f32 {
    if char >= len(default_font) do return 0

    ch := default_font[char]

    char_width  := ch.width * size
    char_height := ch.height * size

    pos_x := x + ch.left * size
    pos_y := y + ch.bottom * size + size * 0.9 // TODO: Fix this

    u_left   := ch.left_uv
    u_right  := ch.right_uv
    v_top    := ch.top_uv
    v_bottom := ch.bottom_uv

    verts := []Vertex{
        {{pos_x, pos_y + char_height}, {u_left, v_top}, color},
        {{pos_x, pos_y}, {u_left, v_bottom}, color},
        {{pos_x + char_width, pos_y}, {u_right, v_bottom}, color},

        {{pos_x, pos_y + char_height}, {u_left, v_top}, color},
        {{pos_x + char_width, pos_y}, {u_right, v_bottom}, color},
        {{pos_x + char_width, pos_y + char_height}, {u_right, v_top}, color},
    }

    copy(verticies[verticies_count:verticies_count + len(verts)], verts[:])
    verticies_count += len(verts)

    return ch.advance * size
}

screenPxRange :: 0.063

draw_text :: proc(text: string, x, y, size: f32, color: Color, boldness : f32 = 1.0) {
    if(verticies_count > 0) {
        end_render()
    }

    use_texture(font_texture)

    update_constant_buffer({size * screenPxRange * boldness})

	device_context->PSSetShader(font_shader, nil, 0)

    cursor_x := x

    y := y

    for char in text {
        ch := char

        if ch == '\n' {
            cursor_x = x
            y += size
            continue
        }

        if ch == ' ' {
            cursor_x += default_font[' '].advance * size
            continue
        }

        if ch >= 512 || default_font[ch].advance == 0.0 {
            ch = '?'
        }

        advance := draw_char(int(ch), cursor_x, y, size, color)
        cursor_x += advance
    }

    end_render()

	device_context->PSSetShader(pixel_shader, nil, 0)
}

measure_text :: proc(text: string, size: f32) -> f32 {
    width: f32 = 0

    for char in text {
        if char == '\n' {
            break
        }

        #no_bounds_check if char := int(char); char < len(default_font) {
            width += default_font[char].advance * size
        }
    }

    return width
}

measure_text_fits :: proc(text: string, size: f32, max_width: f32, tolerance: f32 = 0) -> (width: f32, chars: int) {
    for char in text {
        if char == '\n' {
            break
        }

        #no_bounds_check if char := int(char); char < len(default_font) {
            my_width := default_font[char].advance * size
            (width + my_width * (1 - tolerance) <= max_width) or_break
            width += my_width
            chars += 1
        }
    }
    return
}

TextAlign :: enum {
    LEFT,
    CENTER,
    RIGHT,
}

draw_text_aligned :: proc(text: string, x, y, size: f32, color: Color, align: TextAlign) {
    if ctx.is_minimized do return

    final_x := x

    switch align {
    case .CENTER:
        text_width := measure_text(text, size)
        final_x = x - text_width / 2
    case .RIGHT:
        text_width := measure_text(text, size)
        final_x = x - text_width
    case .LEFT:
    }

    draw_text(text, final_x, y, size, color)
}

draw_text_wrapped :: proc(text: string, x, y, max_width, size: f32, color: Color) {
    if ctx.is_minimized do return

    if(verticies_count > 0) {
        end_render()
    }

    use_texture(font_texture)

    update_constant_buffer({size * screenPxRange})

	device_context->PSSetShader(font_shader, nil, 0)
    device_context->PSSetConstantBuffers(0, 1, &constant_buffer)

    cursor_x := x
    cursor_y := y
    line_height := size

    words := strings.split(text, " ")
    defer delete(words)

    for word in words {
        word_width := measure_text(word, size)
        space_width := default_font[' '].advance * size

        if cursor_x + word_width > x + max_width && cursor_x > x {
            cursor_x = x
            cursor_y += line_height + 4
        }

        for char in word {
            ch := char

            if ch >= 512 || default_font[ch].advance == 0.0 {
                ch = '?'
            }

            advance := draw_char(int(ch), cursor_x, cursor_y, size, color)
            cursor_x += advance
        }

        cursor_x += space_width
    }

    end_render()

	device_context->PSSetShader(pixel_shader, nil, 0)
}


// For generating fonts

// .\msdf-atlas-gen.exe -font .\Inter.ttf -format png -imageout font.png -csv font.csv -size 32 -outerempadding 0.05 -pxrange 2 -yorigin top -charset .\ascii-tr.txt
// Set width and height in generate.odin
// odin run .\generate.odin -file

/*
package main

font_csv := #load("font.csv", string)

texture_width := 272
texture_height := 272

Character :: struct {
    advance: f32,

    left   : f32,
    bottom : f32,
    right  : f32,
    top    : f32,

    left_uv   : f32,
    bottom_uv : f32,
    right_uv  : f32,
    top_uv    : f32,

    width  : f32,
    height : f32,
}

import "core:fmt"
import "core:strconv"
import "core:encoding/csv"

main :: proc() {
    r: csv.Reader
    r.trim_leading_space  = true
    r.reuse_record        = true
    r.reuse_record_buffer = true
    defer csv.reader_destroy(&r)

    csv.reader_init_with_string(&r, font_csv)

    for r, _, err in csv.iterator_next(&r) {
        assert(err == nil)

        char := strconv.atoi(r[0])

        advance := f32(strconv.atof(r[1]))

        left    := f32(strconv.atof(r[2]))
        bottom  := f32(strconv.atof(r[3]))
        right   := f32(strconv.atof(r[4]))
        top     := f32(strconv.atof(r[5]))

        inv_tex_width  := 1.0 / f32(texture_width)
        inv_tex_height := 1.0 / f32(texture_height)

        left_px    := f32(strconv.atof(r[6])) * inv_tex_width
        bottom_px  := f32(strconv.atof(r[7])) * inv_tex_width
        right_px   := f32(strconv.atof(r[8])) * inv_tex_height
        top_px     := f32(strconv.atof(r[9])) * inv_tex_height

        width  := (right - left)
        height := (top - bottom)

        character := Character{advance, left, bottom, right, top, left_px, bottom_px, right_px, top_px, width, height}

        fmt.println(char, "=", character)
    }
}
*/