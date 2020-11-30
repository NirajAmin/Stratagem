import SpriteKit

class Planet {
    var planetID: Int!
    
    // Later when city count/position is random these will need to be procedurally generated
    var cities: [City] = []
    let cityMapping = [
        CGRect(x: 0.705, y: 0.431, width: 0.145, height: 0.139),
        //CGRect(x: 353, y: 183, width: 144, height: 99),
        //CGRect(x: 392, y: 148, width: 142, height: 82)
    ]
    
    init(planetID: Int) {
        self.planetID = planetID
    }
    
    func generateNewCity() {
        let city = City()
        city.initCity(cityName: "City Name")
        cities.append(city)
    }
}

struct PlanetDescription {
    
}
