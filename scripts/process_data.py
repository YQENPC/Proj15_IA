import json
import sys
import matplotlib.pyplot as plt

def main():
    if len(sys.argv) < 3:
        print("Error: Provide JSON file and output image path")
        sys.exit(1)
    
    json_file = sys.argv[1]
    output_image = sys.argv[2]
    
    try:
        with open(json_file, 'r', encoding='utf-8-sig') as f:
            data = json.load(f)
        
        # Example: Plot number of tiles per node type
        node_types = {}
        for node_name, node_data in data.get("nodes", {}).items():
            node_type = node_name.split('_')[0]  # Extract type from name
            tile_count = len(node_data.get("tiles", []))
            node_types[node_type] = node_types.get(node_type, 0) + tile_count
        
        # Create plot
        plt.figure(figsize=(10, 6))
        plt.bar(node_types.keys(), node_types.values())
        plt.xlabel("Node Type")
        plt.ylabel("Number of Tiles")
        plt.title("Tiles per Node Type")
        plt.xticks(rotation=45)
        plt.tight_layout()
        
        # Save as PNG
        plt.savefig(output_image, dpi=100)
        print(f"Plot saved to {output_image}")
        plt.close()
        
    except FileNotFoundError:
        print(f"Error: File '{json_file}' not found")
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
