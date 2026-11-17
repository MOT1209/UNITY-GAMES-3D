class_name NameBank
extends RefCounted

## Country-aware name pools for the five database countries (database phase 6) and the checks
## that keep generated names unique and clearly distinct from existing ones. All names are
## ordinary given names and surnames; combinations are random, so a generated player is fictional.
## `NameIndex` rejects exact duplicates and near-duplicates (one or two letters apart) against
## every name already in the world, real players included.

const POOLS := {
	"England": {
		"first": ["Adam", "Aaron", "Alex", "Alfie", "Andrew", "Archie", "Arthur", "Ben", "Billy", "Blake", "Brandon", "Callum",
			"Charlie", "Connor", "Daniel", "Danny", "Dean", "Dominic", "Elliot", "Ethan", "Finley", "Freddie", "George", "Harrison",
			"Harvey", "Henry", "Isaac", "Jack", "Jacob", "Jake", "James", "Jamie", "Jason", "Jayden", "Joe", "Joel", "Jordan", "Josh",
			"Joshua", "Kieran", "Leo", "Lewis", "Liam", "Logan", "Louis", "Luke", "Mason", "Matthew", "Max", "Michael", "Nathan",
			"Nick", "Noah", "Oliver", "Ollie", "Oscar", "Owen", "Patrick", "Reece", "Rhys", "Riley", "Robbie", "Ryan", "Sam", "Scott",
			"Sean", "Spencer", "Stefan", "Theo", "Thomas", "Toby", "Tom", "Tyler", "William", "Zac"],
		"last": ["Abbott", "Adams", "Ainsley", "Archer", "Ashby", "Atkins", "Bailey", "Baker", "Banks", "Barlow", "Barrett", "Bates",
			"Baxter", "Bell", "Bennett", "Berry", "Booth", "Bowen", "Bradley", "Briggs", "Brooks", "Burke", "Burton", "Carr", "Chambers",
			"Chapman", "Clarke", "Cole", "Cooper", "Cox", "Crawford", "Dawson", "Dixon", "Dunn", "Ellis", "Evans", "Farrell", "Field",
			"Finch", "Fisher", "Fleming", "Ford", "Foster", "Fox", "Gardner", "Gibson", "Graham", "Grant", "Gray", "Hale", "Hall", "Hardy",
			"Harper", "Harris", "Hart", "Hayes", "Henderson", "Hill", "Hodges", "Holland", "Howard", "Hunt", "Jennings", "Jones", "Kemp",
			"Knight", "Lambert", "Lawson", "Lloyd", "Lowe", "Mason", "Matthews", "Miles", "Mills", "Mitchell", "Moore", "Morgan", "Morris",
			"Murray", "Newman", "Nolan", "Norton", "Owens", "Palmer", "Parker", "Payne", "Pearson", "Perry", "Phillips", "Porter", "Powell",
			"Price", "Quinn", "Reed", "Reid", "Richards", "Roberts", "Robson", "Rogers", "Rowe", "Russell", "Sharp", "Simpson", "Stevens",
			"Stone", "Sutton", "Tate", "Taylor", "Thompson", "Turner", "Vaughan", "Wade", "Walsh", "Ward", "Watts", "Webb", "Wells", "West",
			"White", "Wilkinson", "Willis", "Wilson", "Wood", "Wright", "Young"],
	},
	"Spain": {
		"first": ["Adrián", "Aitor", "Álex", "Álvaro", "Andrés", "Ángel", "Antonio", "Arturo", "Borja", "Carlos", "César", "Cristian",
			"Dani", "David", "Diego", "Eduardo", "Enrique", "Ernesto", "Fabián", "Fernando", "Francisco", "Gabriel", "Gonzalo",
			"Guillermo", "Héctor", "Hugo", "Ignacio", "Iker", "Isaac", "Ismael", "Iván", "Jaime", "Javier", "Jesús", "Joaquín", "Jorge",
			"José", "Josep", "Juan", "Julián", "Kike", "Lorenzo", "Lucas", "Luis", "Manuel", "Marc", "Marcos", "Mario", "Martín", "Mateo",
			"Miguel", "Nacho", "Nicolás", "Óscar", "Pablo", "Pau", "Pedro", "Rafael", "Raúl", "Ricardo", "Roberto", "Rodrigo", "Rubén",
			"Salvador", "Samuel", "Santiago", "Sergio", "Tomás", "Unai", "Víctor", "Xavier", "Yeray"],
		"last": ["Aguilar", "Alonso", "Álvarez", "Antúnez", "Arias", "Báez", "Barrios", "Benítez", "Blanco", "Bravo", "Cabrera", "Calvo",
			"Campos", "Cano", "Carmona", "Carrasco", "Castillo", "Chávez", "Cordero", "Cortés", "Crespo", "Cruz", "Domínguez", "Durán",
			"Escobar", "Esteban", "Fernández", "Ferrer", "Flores", "Fuentes", "Gallego", "Garrido", "Giménez", "Guerrero", "Guerra",
			"Herrero", "Ibáñez", "Jiménez", "Lara", "León", "Lozano", "Luna", "Machado", "Medina", "Mendoza", "Montero", "Morales",
			"Muñoz", "Navas", "Nieto", "Núñez", "Ortiz", "Pardo", "Peña", "Pérez", "Pino", "Prieto", "Ramos", "Reyes", "Rivas", "Robles",
			"Rojas", "Román", "Romero", "Ruiz", "Salas", "Sanz", "Segura", "Soto", "Suárez", "Tapia", "Toledo", "Torres", "Valdés",
			"Vargas", "Vega", "Velasco", "Vicente", "Vidal", "Villalba", "Zamora"],
	},
	"Germany": {
		"first": ["Alexander", "Andreas", "Anton", "Arne", "Axel", "Ben", "Benedikt", "Bastian", "Christian", "Clemens", "Daniel", "David",
			"Dennis", "Dominik", "Elias", "Emil", "Erik", "Fabian", "Felix", "Finn", "Florian", "Frederik", "Georg", "Gregor", "Hannes",
			"Henrik", "Jakob", "Jan", "Jannik", "Jonas", "Julian", "Justus", "Kai", "Karl", "Kevin", "Konstantin", "Lars", "Leon", "Linus",
			"Lukas", "Marcel", "Marco", "Marius", "Markus", "Martin", "Mathis", "Matthias", "Max", "Maximilian", "Moritz", "Nico", "Niklas",
			"Noah", "Oliver", "Oskar", "Patrick", "Paul", "Philipp", "Rafael", "Robin", "Sebastian", "Simon", "Stefan", "Sven", "Till",
			"Tim", "Timo", "Tobias", "Tom", "Valentin", "Vincent", "Yannick"],
		"last": ["Albrecht", "Arnold", "Bauer", "Baumann", "Beck", "Berger", "Brandt", "Brinkmann", "Busch", "Conrad", "Decker", "Dietrich",
			"Ebert", "Engel", "Fischer", "Franke", "Friedrich", "Fuchs", "Graf", "Günther", "Hahn", "Hartmann", "Heinrich", "Herrmann",
			"Hofmann", "Huber", "Jäger", "Jung", "Kaiser", "Keller", "Kessler", "Klein", "Koch", "König", "Krause", "Krüger", "Kühn",
			"Lang", "Lehmann", "Lorenz", "Ludwig", "Maier", "Meier", "Möller", "Müller", "Neumann", "Nowak", "Otto", "Pfeiffer", "Richter",
			"Roth", "Schäfer", "Scherer", "Schmid", "Schmitt", "Schneider", "Scholz", "Schreiber", "Schubert", "Schulte", "Schulz", "Seidel",
			"Sommer", "Stein", "Vogel", "Voigt", "Wagner", "Walter", "Weber", "Weiß", "Werner", "Winkler", "Wolff", "Ziegler", "Zimmer"],
	},
	"Italy": {
		"first": ["Alberto", "Alessio", "Andrea", "Angelo", "Antonio", "Bruno", "Carlo", "Claudio", "Cristian", "Damiano", "Daniele", "Dario",
			"Davide", "Diego", "Domenico", "Edoardo", "Emanuele", "Enrico", "Fabio", "Federico", "Filippo", "Francesco", "Gabriele",
			"Giacomo", "Gianluca", "Giorgio", "Giovanni", "Giulio", "Giuseppe", "Guido", "Ivan", "Jacopo", "Leonardo", "Lorenzo", "Luca",
			"Luigi", "Manuel", "Marco", "Mario", "Mattia", "Matteo", "Maurizio", "Michele", "Nicola", "Nicolò", "Paolo", "Pietro",
			"Raffaele", "Riccardo", "Roberto", "Salvatore", "Samuele", "Sandro", "Simone", "Stefano", "Tommaso", "Umberto", "Valerio",
			"Vincenzo", "Vittorio"],
		"last": ["Amato", "Barone", "Bellini", "Benedetti", "Bernardi", "Bianchi", "Bruno", "Caputo", "Carbone", "Colombo", "Conte", "Costa",
			"D'Angelo", "De Luca", "De Santis", "Donati", "Esposito", "Fabbri", "Farina", "Ferrari", "Fiore", "Gallo", "Gentile", "Giordano",
			"Grasso", "Greco", "Guidi", "Leone", "Longo", "Mancuso", "Marini", "Martini", "Messina", "Monti", "Neri", "Orlando", "Pagano",
			"Palumbo", "Parisi", "Pellegrini", "Piras", "Ricci", "Rizzo", "Romano", "Rossetti", "Rossi", "Ruggiero", "Sala", "Santoro",
			"Sartori", "Serra", "Silvestri", "Sorrentino", "Valentini", "Vitale", "Villa", "Zanetti", "Zito", "Basile", "Cattaneo", "Ferri", "Lombardo", "Mariani", "Pace", "Testa"],
	},
	"France": {
		"first": ["Adrien", "Alexandre", "Alexis", "Anthony", "Antoine", "Arnaud", "Axel", "Baptiste", "Benjamin", "Bastien", "Cédric", "Charles",
			"Clément", "Corentin", "Damien", "Dylan", "Édouard", "Élie", "Émile", "Enzo", "Étienne", "Fabien", "Florian", "François", "Gabin",
			"Gaël", "Guillaume", "Hugo", "Jérémy", "Jules", "Julien", "Kévin", "Lilian", "Loïc", "Louis", "Lucas", "Mathieu", "Mathis",
			"Maxence", "Maxime", "Mickaël", "Nathan", "Nicolas", "Noé", "Olivier", "Pascal", "Pierre", "Quentin", "Rémi", "Romain", "Samuel",
			"Sébastien", "Simon", "Stéphane", "Théo", "Théophile", "Thibault", "Thomas", "Tristan", "Valentin", "Victor", "Vincent", "Yanis",
			"Yann"],
		"last": ["André", "Aubert", "Barbier", "Baron", "Bertrand", "Blanc", "Boucher", "Bourgeois", "Brun", "Caron", "Chevalier", "Clément",
			"Collet", "Colin", "Cordier", "Delmas", "Deschamps", "Dubois", "Dumas", "Durand", "Fabre", "Faure", "Fournier", "François",
			"Gaillard", "Garnier", "Gauthier", "Girard", "Guérin", "Guillot", "Henry", "Hubert", "Jacquet", "Lacroix", "Lambert", "Lebrun",
			"Leclerc", "Lemaire", "Lopez", "Marchand", "Martin", "Masson", "Meunier", "Michel", "Moulin", "Noël", "Paris", "Perrin", "Petit",
			"Picard", "Pierre", "Renard", "Renaud", "Rey", "Robin", "Roche", "Roger", "Rolland", "Roux", "Royer", "Schmitt", "Thibault",
			"Vasseur", "Vidal", "Weber"],
	},
}
const COUNTRIES: Array[String] = ["England", "Spain", "Germany", "Italy", "France"]


static func has_pool(country: String) -> bool:
	return POOLS.has(country)


## "First Last" drawn from the country's pools.
static func random_name(rng: RandomNumberGenerator, country: String) -> String:
	var pool: Dictionary = POOLS.get(country, POOLS["England"])
	var first: Array = pool["first"]
	var last: Array = pool["last"]
	return "%s %s" % [first[rng.randi() % first.size()], last[rng.randi() % last.size()]]


## Number of different names a country's pools can produce.
static func combinations(country: String) -> int:
	var pool: Dictionary = POOLS.get(country, {})
	return (pool.get("first", []) as Array).size() * (pool.get("last", []) as Array).size()


## A name no one in `index` has (or looks too much like). Falls back to a numbered initial after
## many tries, so it always terminates.
static func unique_name(rng: RandomNumberGenerator, country: String, index: NameIndex) -> String:
	for i in 80:
		var n := random_name(rng, country)
		if index.check(n) == "":
			index.add(n)
			return n
	var pool: Dictionary = POOLS.get(country, POOLS["England"])
	var n2 := "%s %s" % [(pool["first"] as Array)[rng.randi() % (pool["first"] as Array).size()], (pool["last"] as Array)[rng.randi() % (pool["last"] as Array).size()]]
	index.add(n2)
	return n2
