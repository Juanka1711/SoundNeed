from PIL import Image

img = Image.open("assets/icon/app_icon.png").convert("RGBA")

canvas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))

safe_zone = int(1024 * 0.66)
logo_size = int(safe_zone * 1.0)

logo = img.resize((logo_size, logo_size), Image.LANCZOS)

pos = ((1024 - logo_size) // 2, (1024 - logo_size) // 2)
canvas.paste(logo, pos, logo)

canvas.save("assets/icon/app_icon_foreground.png")
print("Foreground creado: assets/icon/app_icon_foreground.png")