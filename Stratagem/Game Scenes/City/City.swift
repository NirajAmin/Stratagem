import SpriteKit
import SKTiled

public class City {
    /// Unique city name (no spaces)
    var cityName: String! // Firebase
    var planetName: String!
    
    /// Owner that has power to edit
    var owner: String? // Firebase
    
    /// City size
    let cityWidth: Int = 20
    let cityHeight: Int = 20
    
    /// City terrain, a 2d array of CityTiles
    var cityTerrain: [[CityTile]]!
    /// City terrain as an array of Ints. Should only be used when initting and loading city
    var cityTerrainInt: [[Int]]! // Firebase
    
    /// Tilemap
    weak var tilemap: SKTilemap!
    
    /// Hudnode ref used for error messages
    weak var hudNode: HudNode?
    
    /// TIme since last second, used to update firebase
    var secondDelta: CGFloat = 0
    
    /// Stats
    var resources: [ResourceTypes: CGFloat] = [.POPULATION: 300, .CREDITS: 1000, .METAL: 50] // Firebase
    var resourcesCap: [ResourceTypes: CGFloat] = [.POPULATION: 3000, .CREDITS: 100000, .METAL: 500]
    var units: [UnitType: Int] =
        [.BRAWLER: 3, .SNIPER: 1, .FIGHTER: 5]
    
    /// Initializes city variables (required). If not terrain is provided, create a new city
    func initCity(cityName: String, planetName: String, owner: String? = nil, terrain: [[Int]]? = nil) {
        self.cityName = cityName
        self.planetName = planetName
        self.owner = owner
        
        if let terrain = terrain {
            cityTerrainInt = terrain
        } else {
            cityTerrainInt = makeCityTerrain()
        }
    }
    
    func update(deltaTime: CGFloat) {
        // Residential
        var totalPopRate = CGFloat(0)
        var totalPopCap = resourcesCap[.POPULATION]!
        if let cityTerrain = cityTerrain {
            for cityTile in cityTerrain.joined().filter({ $0.tileType == .RESIDENTIAL }) {
                totalPopCap += CGFloat((cityTile.building as! ResidentialBuilding).popCap)
                totalPopRate += (cityTile.building as! ResidentialBuilding).popRate
            }
            
            let pop = resources[.POPULATION]!
            resources[.POPULATION] = CGFloat.minimum(pop + pop * totalPopRate * deltaTime, CGFloat(totalPopCap))
            resourcesCap[.POPULATION] = totalPopCap
        }
        
        // Industrial
        if let cityTerrain = cityTerrain {
            for cityTile in cityTerrain.joined().filter({ $0.tileType == .INDUSTRIAL }) {
                _ = tryDeductFunds(costs: (cityTile.building as! IndustrialBuilding).consumes, deltaTime: deltaTime)
                tryAddFunds(funds: (cityTile.building as! IndustrialBuilding).produces, deltaTime: deltaTime)
            }
        }
        
        // Military
        if let cityTerrain = cityTerrain {
            for cityTile in cityTerrain.joined().filter({ $0.tileType == .MILITARY }) {
                let newUnit: Units? = (cityTile.building as? MilitaryBuilding)?.update(deltaTime)
                
                if let newUnit = newUnit {
                    units[newUnit.unitType!]! += 1
                    Global.hfGamePusher.uploadUnits(cityName: cityName!, units: units)
                }
            }
        }
        // Credits- for now, 5% of population / sec
        tryAddFunds(funds: [.CREDITS: (0.05 * resources[.POPULATION]!)], deltaTime: deltaTime)
        
        // Metal- 1/sec so player doesn't get softlocked
        tryAddFunds(funds: [.METAL: 1], deltaTime: deltaTime)
        
        secondDelta += deltaTime
        if secondDelta >= 5 {
            Global.hfGamePusher.uploadResources(cityName: cityName!, name: "resources", resources: resources)

            secondDelta = 0
        }
    }
    
    /// Try to replace firstTile with secondTile given its global ID
    func changeTileAtLoc(firstTile: SKTile, secondTileID: Int, isFree: Bool = false, recusive: Bool = true) {
        var secondTileID = secondTileID
        
        if let tileLayer = firstTile.layer {
            if tileLayer.name! == "Tile Layer 1" {
                let x = Int(firstTile.tileCoord!.x)
                let y = Int(firstTile.tileCoord!.y)
                
                // Constraints that ALL tiles have to respect
                if cityTerrain[x][y].isEditable == true {
                    // Build a building, satisfying the building's constraints
                    let cityTile = CityTile()
                    var newTileData = tileLayer.getTileData(globalID: secondTileID)!
                    
                    // If second tile is ground (destroying), make sure first tile isn't ground
                    if newTileData.properties["type"] == "ground" && firstTile.tileData.properties["type"] == "ground" {
                        hudNode!.inlineErrorMessage(errorMessage: "Can't destroy ground")
                        return
                    }
                    
                    let message = cityTile.initTile(tile: firstTile, newTileData: newTileData, cityTerrain: cityTerrain, isEditable: true)
                    
                    if message == "true" {
                        // If it's a building, check if player has the resources and then subtract it
                        if let building = cityTile.building {
                            if !isFree {
                                let deductedFunds = tryDeductFunds(costs: building.costs)
                                if !deductedFunds {
                                    hudNode!.inlineErrorMessage(errorMessage: "Insufficient funds")
                                    return
                                }
                            }
                            
                            if let road = building as? Road {
                                road.updateRoadGID(city: self, currentCoords: firstTile.tileCoord!)
                                secondTileID = road.globalID
                                newTileData = tileLayer.getTileData(globalID: secondTileID)!
                            }
                        }
                        
                        let newTexture = newTileData.texture!
                        
                        newTexture.filteringMode = .nearest
                        firstTile.texture = newTileData.texture
                        firstTile.tileData = newTileData
                        
                        // Update my cityTerrain array
                        cityTerrain[x][y] = cityTile
                        cityTerrainInt[x][y] = secondTileID
                        
                        // Update the adjacent tiles if they're road
                        if recusive {
                            let coordUpperLeft = CGPoint(x: x - 1, y: y)
                            let coordUpperRight = CGPoint(x: x, y: y - 1)
                            let coordLowerRight = CGPoint(x: x + 1, y: y)
                            let coordLowerLeft = CGPoint(x: x, y: y + 1)
                            let coordsAdjacent = [coordUpperLeft, coordUpperRight, coordLowerRight, coordLowerLeft]
                            
                            for coordAdjacent in coordsAdjacent {
                                let cityTile = cityTerrain[Int(coordAdjacent.x)][Int(coordAdjacent.y)]
                                if cityTile.building is Road {
                                    changeTileAtLoc(firstTile: cityTile.tile!, secondTileID: 96, isFree: true, recusive: false)
                                }
                            }
                        }
                        
                        Global.hfGamePusher.uploadCityTerrain(cityName: cityName, cityTerrainInt: cityTerrainInt)
                    } else {
                        hudNode!.inlineErrorMessage(errorMessage: message)
                    }
                }
            } else {
                hudNode!.inlineErrorMessage(errorMessage: "Tile is outside of editable map")
            }
        }
    }
    
    /// Tries to deduct funds from gamevars. Returns true if they had enough funds
    func tryDeductFunds(costs: [ResourceTypes: CGFloat], deltaTime: CGFloat = 1) -> Bool {
        var sufficientFunds = true
        for (type, cost) in costs {
            if resources[type]! < cost * deltaTime {
                sufficientFunds = false
            }
        }
        
        
        // Now subtract it
        if sufficientFunds {
            for (type, cost) in costs {
                resources[type]! -= cost * deltaTime
            }
        } else {
            return false
        }
        return true
    }
    
    /// Tries to add funds from gamevars.
    func tryAddFunds(funds: [ResourceTypes: CGFloat], deltaTime: CGFloat = 1) {
        for (type, fund) in funds {
            resources[type]! = min(fund * deltaTime + resources[type]!, resourcesCap[type]!)
        }
    }
    
    // Creates CityTiles from a tilemap and loads it into cityTerrain
    func loadTilemap(_ tilemap: SKTilemap) {
        self.tilemap = tilemap
        
        cityTerrain = Array(repeating: Array(repeating: CityTile(), count: cityHeight), count: cityWidth)
        let layer = tilemap.getLayers(named: "Tile Layer 1")[0] as? SKTileLayer
        for row in 0..<cityWidth {
            for col in 0..<cityHeight {
                let cityTile = CityTile()
                
                // Add padding tiles around the playable area
                var isEditable = true
                if row < 2 || row >= cityWidth - 2 || col < 2 || col >= cityHeight - 2 {
                    isEditable = false
                }
                
                let tile = (layer?.tileAt(row, col))!
                _ = cityTile.initTile(tile: tile, newTileData: tile.tileData, cityTerrain: nil, isEditable: isEditable)
                cityTerrain[row][col] = cityTile
            }
        }
    }
    
    // Creates CityTiles from a tilemap and loads it into cityTerrain
    func loadExistingTilemap(_ tilemap: SKTilemap) {
        self.tilemap = tilemap
        
        let layer = tilemap.getLayers(named: "Tile Layer 1")[0] as? SKTileLayer
        for row in 0..<cityWidth {
            for col in 0..<cityHeight {
                let tile = (layer?.tileAt(row, col))!
                let cityTile = cityTerrain[row][col]
                cityTile.tile = tile
                cityTerrain[row][col] = cityTile
            }
        }
    }
    
    /// Creates file [cityName].tmx from cityTerrainInt
    func createTMXFile() {
        // Copy tsx file
        copyFileToDocumentsFolder(nameForFile: "Tileset", extForFile: "tsx")
        
        // Create tmx file
        var layer1 = ""
        var layer2 = ""
        for col in 0..<cityHeight {
            for row in 0..<cityWidth {
                layer1 = layer1 + "\(cityTerrainInt[row][col]),"
            }
            layer1 = layer1 + " \n"
        }
        layer1 = String(layer1.dropLast(3)) + "\n"
        for _ in 0..<cityWidth {
            for _ in 0..<cityHeight {
                layer2 = layer2 + "0,"
            }
            layer2 = layer2 + " \n"
        }
        layer2 = String(layer2.dropLast(3)) + "\n"
        
        var text = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<map version=\"1.4\" tiledversion=\"1.4.3\" orientation=\"isometric\" renderorder=\"right-down\" width=\"" + String(cityWidth) + "\" height=\""
        text = text + String(cityHeight) + "\" tilewidth=\"200\" tileheight=\"100\" infinite=\"0\" staggeraxis=\"y\" staggerindex=\"odd\" nextlayerid=\"11\" nextobjectid=\"1\">\n <tileset firstgid=\"1\" source=\"Tileset.tsx\"/>\n <layer id=\"8\" name=\"Tile Layer 1\" width=\"" + String(cityWidth) + "\" height=\""
        text = text + String(cityHeight) + "\">\n  <data encoding=\"csv\">\n" + layer1 + "</data>\n </layer>\n </map>\n"
        
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = dir.appendingPathComponent("City.tmx")
            
            do {
                try text.write(to: fileURL, atomically: true, encoding: .utf8)
            }
            catch {
                print("Unable to write " + fileURL.absoluteString)
            }
        }
    }
    
    /// Creates a 2d array of integers representing the tile id using perlin noise
    private func makeCityTerrain() -> [[Int]] {
        // Make sure the user doesn't get too unlucky
        var numResourceTiles = 0
        var rectTerrain: [[Int]] = Array(repeating: Array(repeating: 0, count: cityHeight), count: cityWidth)
        let noisemap = Perlin2D().octaveMatrix(width: cityWidth, height: cityHeight, scale: 10, octaves: 6, persistance: 0.25)
        while numResourceTiles < 6 {
            numResourceTiles = 0
            let resourceNoiseMap = Perlin2D().octaveMatrix(width: cityWidth, height: cityHeight, scale: 15, octaves: 6, persistance: 0.25)
            
            // Baseline terrain with grass, sand, and water tiles. Then add resource tiles
            for row in 0..<cityWidth {
                for col in 0..<cityHeight {
                    let terrainHeight = noisemap[row][col]
                    
                    if terrainHeight <= 0.4 {
                        rectTerrain[row][col] = 3
                    } else if terrainHeight <= 0.45 {
                        rectTerrain[row][col] = 2
                    } else if terrainHeight <= 1 {
                        // If there's a resource tile, add that instead of grass
                        if resourceNoiseMap[row][col] < 0.35 {
                            // Iron
                            rectTerrain[row][col] = 5
                            if !(row < 2 || row >= cityWidth - 2 || col < 2 || col >= cityHeight - 2) {
                                numResourceTiles += 1
                            }
                        } else if resourceNoiseMap[row][col] < 0.7 {
                            // Grass
                            rectTerrain[row][col] = 1
                        } else if resourceNoiseMap[row][col] <= 1 {
                            // Oil
                            rectTerrain[row][col] = 4
                            if !(row < 2 || row >= cityWidth - 2 || col < 2 || col >= cityHeight - 2) {
                                numResourceTiles += 1
                            }
                        }
                    }
                }
            }
        }
        return rectTerrain
    }
    
    private func copyFileToDocumentsFolder(nameForFile: String, extForFile: String) {
        
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let destURL = documentsURL!.appendingPathComponent(nameForFile).appendingPathExtension(extForFile)
        guard let sourceURL = Bundle.main.url(forResource: nameForFile, withExtension: extForFile)
        else {
            print("Source File not found.")
            return
        }
        let fileManager = FileManager.default
        do {
            try? fileManager.removeItem(at: destURL)
            try fileManager.copyItem(at: sourceURL, to: destURL)
        } catch {
            print("Unable to copy file")
        }
    }
}
